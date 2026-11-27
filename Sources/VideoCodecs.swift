import Foundation
import VideoToolbox
import WebKit

/// Hardware-decoded video on YouTube.
///
/// YouTube picks the most compact video format the browser says it can play: VP9, or AV1 on
/// newer machines. On a Mac whose graphics chip can't decode those, WebKit still says yes and
/// decodes them on the processor: a 1080p60 video kept the CPU busy, ran the fans, took longer
/// to start and dropped frames. Every Mac decodes H.264 in hardware, so on those Macs YouTube is
/// told only about the formats this Mac's hardware can decode, and it sends H.264 instead.
/// Macs that decode VP9 or AV1 in hardware keep them (nothing changes there).
///
/// It runs on YouTube's pages and YouTube videos embedded in other sites, nowhere else.
enum VideoCodecs {
    /// The codec names to keep from YouTube on this Mac (empty when its hardware decodes them all).
    static let hidden: [String] = {
        if ProcessInfo.processInfo.environment["UFOLIO_CODECS_OFF"] != nil { return [] }   // measuring only
        var names: [String] = []
        if !VTIsHardwareDecodeSupported(0x7670_3039) { names += ["vp9", "vp09"] }   // 'vp09'
        if !VTIsHardwareDecodeSupported(0x6176_3031) { names += ["av01"] }          // 'av01'
        return names
    }()

    /// Nil when there's nothing to hide (the script isn't added to pages at all then).
    static let script: WKUserScript? = {
        guard !hidden.isEmpty else { return nil }
        let pattern = hidden.joined(separator: "|")
        let source = """
        (function () {
          if (!/(^|\\.)(youtube\\.com|youtube-nocookie\\.com)$/.test(location.hostname)) return;
          var soft = /(^|[^a-z0-9])(\(pattern))/i;
          function wrap(owner, name, fallback) {
            var original = owner && owner[name];
            if (typeof original !== 'function') return;
            owner[name] = function (type) {
              if (typeof type === 'string' && soft.test(type)) return fallback;
              return original.apply(this, arguments);
            };
          }
          wrap(window.MediaSource, 'isTypeSupported', false);
          wrap(window.ManagedMediaSource, 'isTypeSupported', false);
          wrap(window.HTMLMediaElement && HTMLMediaElement.prototype, 'canPlayType', '');
          var mc = navigator.mediaCapabilities;
          if (mc && typeof mc.decodingInfo === 'function') {
            var decodingInfo = mc.decodingInfo.bind(mc);
            mc.decodingInfo = function (config) {
              var type = config && config.video && config.video.contentType;
              if (typeof type === 'string' && soft.test(type)) {
                return Promise.resolve({ supported: false, smooth: false, powerEfficient: false });
              }
              return decodingInfo(config);
            };
          }
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
    }()
}
