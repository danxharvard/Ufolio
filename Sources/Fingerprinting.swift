import WebKit

/// Fingerprinting protection ("farbling"): sites that try to recognise you by how your Mac
/// draws graphics, plays audio or reports its hardware get answers with a tiny amount of
/// noise. The noise is the same on one site for this session (so sites keep working), but
/// different on every other site and every time Hush starts, so you can't be tracked across
/// them. Strict mode also hides more detail.
enum Fingerprinting {
    /// A fresh secret every launch.
    private static let sessionKey = UUID().uuidString

    static var isEnabled: Bool { Prefs.bool(Prefs.fingerprintProtection) }

    static let standard = make(strict: false)
    static let strict = make(strict: true)

    private static func make(strict: Bool) -> WKUserScript {
        let source = """
        (function () {
          'use strict';
          var KEY = \(String(reflecting: sessionKey)), STRICT = \(strict ? "true" : "false");
          function hash(s) { var h = 2166136261; for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }
          var seed = hash(KEY + '|' + location.hostname);
          function rand(n) { var x = (seed ^ Math.imul((n | 0) + 1, 0x9E3779B1)) >>> 0; x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; return (x >>> 0) / 4294967296; }
          var rate = STRICT ? 0.08 : 0.015;
          function noise(data) {
            for (var i = 0; i < data.length; i += 4) { if (rand(i) < rate) { data[i] = data[i] ^ 1; data[i + 1] = data[i + 1] ^ (rand(i + 1) < 0.5 ? 1 : 0); } }
          }
          // Changed functions still describe themselves as the originals, so pages can't tell.
          var natives = new WeakMap();
          var originalToString = Function.prototype.toString;
          var toStringProxy = new Proxy(originalToString, {
            apply: function (target, self, args) { return Reflect.apply(target, natives.get(self) || self, args); }
          });
          natives.set(toStringProxy, originalToString);
          Function.prototype.toString = toStringProxy;
          function wrap(proto, name, handler) {
            try {
              var original = proto[name];
              if (typeof original !== 'function') return;
              var proxy = new Proxy(original, { apply: function (target, self, args) { return handler(target, self, args); } });
              natives.set(proxy, original);
              proto[name] = proxy;
            } catch (e) {}
          }

          // Canvas: noise in anything read back from a canvas.
          if (window.CanvasRenderingContext2D) {
            wrap(CanvasRenderingContext2D.prototype, 'getImageData', function (target, self, args) {
              var image = Reflect.apply(target, self, args);
              try { noise(image.data); } catch (e) {}
              return image;
            });
          }
          function noisyCopy(canvas) {
            try {
              var w = canvas.width, h = canvas.height;
              if (!w || !h || w * h > 16000000) return canvas;
              var copy = document.createElement('canvas'); copy.width = w; copy.height = h;
              var ctx = copy.getContext('2d'); ctx.drawImage(canvas, 0, 0);
              var image = ctx.getImageData(0, 0, w, h);   // already noised by the wrapper above
              ctx.putImageData(image, 0, 0);
              return copy;
            } catch (e) { return canvas; }
          }
          if (window.HTMLCanvasElement) {
            ['toDataURL', 'toBlob'].forEach(function (name) {
              wrap(HTMLCanvasElement.prototype, name, function (target, self, args) {
                return Reflect.apply(target, noisyCopy(self), args);
              });
            });
          }

          // WebGL: noise in read-backs, and a generic graphics card name.
          [window.WebGLRenderingContext, window.WebGL2RenderingContext].forEach(function (GL) {
            if (!GL) return;
            wrap(GL.prototype, 'readPixels', function (target, self, args) {
              var result = Reflect.apply(target, self, args);
              try { var px = args[6]; if (px && px.length) noise(px); } catch (e) {}
              return result;
            });
            wrap(GL.prototype, 'getParameter', function (target, self, args) {
              if (args[0] === 0x9245) return 'Apple Inc.';      // UNMASKED_VENDOR_WEBGL
              if (args[0] === 0x9246) return 'Apple GPU';       // UNMASKED_RENDERER_WEBGL
              return Reflect.apply(target, self, args);
            });
          });

          // Audio: tiny, inaudible noise in audio analysis.
          var touched = new WeakSet();
          if (window.AudioBuffer) {
            wrap(AudioBuffer.prototype, 'getChannelData', function (target, self, args) {
              var data = Reflect.apply(target, self, args);
              try {
                if (!touched.has(data)) {
                  touched.add(data);
                  for (var i = 0; i < data.length; i += 97) data[i] += (rand(i) - 0.5) * 1e-7;
                }
              } catch (e) {}
              return data;
            });
          }
          if (window.AnalyserNode) {
            wrap(AnalyserNode.prototype, 'getFloatFrequencyData', function (target, self, args) {
              var result = Reflect.apply(target, self, args);
              try { var a = args[0]; for (var i = 0; i < a.length; i += 11) a[i] += (rand(i) - 0.5) * 0.1; } catch (e) {}
              return result;
            });
          }

          // Hardware: the same answers as most Macs.
          function getter(obj, name, value) {
            try {
              var old = Object.getOwnPropertyDescriptor(obj, name);
              var get = { get [name]() { return value; } }; // named like the original
              var fn = Object.getOwnPropertyDescriptor(get, name).get;
              if (old && old.get) natives.set(fn, old.get);
              Object.defineProperty(obj, name, { get: fn, configurable: true, enumerable: old ? old.enumerable : true });
            } catch (e) {}
          }
          getter(Navigator.prototype, 'hardwareConcurrency', 8);
          if (STRICT) {
            getter(Navigator.prototype, 'maxTouchPoints', 0);
            getter(Screen.prototype, 'availWidth', screen.width);
            getter(Screen.prototype, 'availHeight', screen.height);
            getter(Screen.prototype, 'colorDepth', 24);
            getter(Screen.prototype, 'pixelDepth', 24);
            // Font measuring: a hair of noise in text widths, which fingerprinters use to list your fonts.
            if (window.CanvasRenderingContext2D) {
              wrap(CanvasRenderingContext2D.prototype, 'measureText', function (target, self, args) {
                var m = Reflect.apply(target, self, args);
                try { var w = m.width + (rand(String(args[0]).length + 7) - 0.5) * 0.02; getter(m, 'width', w); } catch (e) {}
                return m;
              });
            }
          }
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
    }
}
