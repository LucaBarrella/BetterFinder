import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import AVKit
import WebKit
import SceneKit
import AVFoundation
import CoreMedia
import ImageIO

// MARK: - Preview kind

private enum PreviewKind {
    case image, pdf, video, audio, web, text, scene3D, generic
}

// MARK: - Router

/// Routes a file URL to the correct renderer based on UTType / extension.
struct FilePreviewContent: View {
    let url: URL
    @State private var scene3DFailed = false

    var body: some View {
        Group {
            switch kind {
            case .image:   ImagePreview(url: url)
            case .pdf:     PDFPreview(url: url)
            case .video:   VideoPreview(url: url)
            case .audio:   AudioPreview(url: url)
            case .web:     WebPreview(url: url)
            case .text:    TextPreview(url: url)
            case .scene3D: Scene3DPreview(url: url, onFailed: { scene3DFailed = true })
            case .generic: GenericPreview(url: url)
            }
        }
        // Re-read `scene3DFailed` to allow fallback
        .id(url.path + (scene3DFailed ? "-ql" : ""))
    }

    // MARK: - Routing logic

    private var kind: PreviewKind {
        let ext  = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)

        if Self.scene3DExtensions.contains(ext) && !scene3DFailed { return .scene3D }

        // SVG via WKWebView (more faithful than NSImage)
        if ext == "svg" || ext == "svgz"             { return .web }

        if type?.conforms(to: .image) == true        { return .image }
        if type?.conforms(to: .pdf)   == true        { return .pdf }

        if Self.videoExtensions.contains(ext) || type?.conforms(to: .movie) == true { return .video }
        if Self.audioExtensions.contains(ext) || type?.conforms(to: .audio) == true { return .audio }

        if Self.webExtensions.contains(ext) || type?.conforms(to: .html) == true { return .web }

        if type?.conforms(to: .text)       == true
        || type?.conforms(to: .sourceCode) == true
        || Self.textExtensions.contains(ext)         { return .text }

        return .generic
    }

    // MARK: - Extension tables

    private static let scene3DExtensions: Set<String> = [
        "scn","dae","abc","obj","usd","usda","usdc","usdz","stl","ply","glb","gltf"
    ]
    private static let videoExtensions: Set<String> = [
        "mp4","m4v","mov","avi","mkv","wmv","flv","webm","mpeg","mpg","3gp","ts"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3","m4a","aac","flac","wav","aiff","aif","ogg","opus","wma","caf","mid","midi"
    ]
    private static let webExtensions: Set<String> = [
        "html","htm","xhtml","webarchive","mhtml"
    ]
    private static let textExtensions: Set<String> = [
        "txt","md","markdown","rst","log","csv","tsv",
        "swift","py","js","ts","jsx","tsx","go","rs","rb","php","java","kt","dart",
        "c","h","cpp","cc","cxx","hpp","m","mm","cs","vb",
        "sh","bash","zsh","fish","ps1","bat","cmd",
        "json","yaml","yml","toml","xml","plist","graphql","sql",
        "css","scss","sass","less",
        "vue","svelte","astro","razor",
        "dockerfile","makefile","gitignore","env","editorconfig"
    ]
}

// MARK: - Image

private struct ImagePreview: View {
    let url: URL
    @State private var image: NSImage?
    @State private var loading = true

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            } else if loading {
                ProgressView().controlSize(.regular)
            } else {
                GenericPreview(url: url)
            }
        }
        .task(id: url) {
            loading = true
            image = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
            loading = false
        }
    }
}

// MARK: - PDF

private struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales               = true
        v.displayMode              = .singlePageContinuous
        v.displayDirection         = .vertical
        v.pageShadowsEnabled       = true
        v.document = PDFDocument(url: url)
        return v
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}

// MARK: - Video

private struct VideoPreview: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle               = .inline
        v.showsFullScreenToggleButton = false
        load(url, into: v, coordinator: context.coordinator)
        return v
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.player?.pause()
        load(url, into: nsView, coordinator: context.coordinator)
    }

    private func load(_ url: URL, into v: AVPlayerView, coordinator: Coordinator) {
        coordinator.loadedURL = url
        let player = AVPlayer(url: url)
        v.player = player
        coordinator.player = player
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        nsView.player = nil
        coordinator.player = nil
    }

    final class Coordinator {
        var player: AVPlayer?
        var loadedURL: URL?
    }
}

// MARK: - Audio

private struct AudioPreview: View {
    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            // Artwork / visual placeholder
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                VStack(spacing: 10) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.quaternary)
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    Text(url.pathExtension.uppercased())
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Player controls
            AudioPlayerView(url: url)
                .frame(height: 54)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

private struct AudioPlayerView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle               = .inline
        v.showsFullScreenToggleButton = false
        load(url, into: v, coordinator: context.coordinator)
        return v
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.player?.pause()
        load(url, into: nsView, coordinator: context.coordinator)
    }

    private func load(_ url: URL, into v: AVPlayerView, coordinator: Coordinator) {
        coordinator.loadedURL = url
        let player = AVPlayer(url: url)
        v.player = player
        coordinator.player = player
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        nsView.player = nil
        coordinator.player = nil
    }

    final class Coordinator {
        var player: AVPlayer?
        var loadedURL: URL?
    }
}

// MARK: - Web (HTML, SVG, WebArchive)

private struct WebPreview: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let v = WKWebView(frame: .zero, configuration: cfg)
        load(url, into: v, coordinator: context.coordinator)
        return v
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Only reload if the URL actually changed — avoids blank flash on every SwiftUI re-render
        guard context.coordinator.loadedURL != url else { return }
        load(url, into: nsView, coordinator: context.coordinator)
    }

    private func load(_ url: URL, into webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadedURL = url
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}

// MARK: - Text / Code

private struct TextPreview: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = buildTextView()
        context.coordinator.textView = tv

        let sv = NSScrollView()
        sv.documentView        = tv
        sv.hasVerticalScroller = true
        sv.autohidesScrollers  = true
        sv.borderType          = .noBorder
        sv.drawsBackground     = false

        loadContent(into: tv)
        return sv
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    // MARK: Helpers

    private func buildTextView() -> NSTextView {
        let tv = NSTextView(frame: .zero)
        tv.isEditable                    = false
        tv.isSelectable                  = true
        tv.isRichText                    = true
        tv.drawsBackground               = true
        tv.backgroundColor               = NSColor.textBackgroundColor
        tv.font                          = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        tv.textColor                     = NSColor.labelColor
        tv.isVerticallyResizable         = true
        tv.isHorizontallyResizable       = false
        tv.autoresizingMask              = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize  = NSSize(width: 0, height: 1_000_000)
        tv.textContainerInset            = NSSize(width: 10, height: 10)
        tv.textStorage?.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        return tv
    }

    private func loadContent(into tv: NSTextView) {
        let capturedURL = url
        let ext = url.pathExtension.lowercased()
        Task.detached(priority: .userInitiated) {
            let text = Self.readText(from: capturedURL)
            await MainActor.run {
                let highlighted: NSAttributedString
                if SyntaxHighlighter.isSupportedExtension(ext) {
                    highlighted = SyntaxHighlighter.highlight(text, forExtension: ext)
                } else {
                    highlighted = NSAttributedString(string: text, attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
                        .foregroundColor: NSColor.labelColor
                    ])
                }
                tv.textStorage?.setAttributedString(highlighted)
            }
        }
    }

    nonisolated private static func readText(from url: URL) -> String {
        var text: String
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            text = s
        } else if let s = try? String(contentsOf: url, encoding: .isoLatin1) {
            text = s
        } else {
            return "(Binary or unreadable file)"
        }
        if text.utf8.count > 300_000 {
            let cutoff = text.utf8.index(text.startIndex, offsetBy: 300_000,
                                         limitedBy: text.endIndex) ?? text.endIndex
            text = String(text[..<cutoff])
            text += "\n\n… (file truncated — showing first 300 KB)"
        }
        return text
    }

    final class Coordinator { weak var textView: NSTextView? }
}

// MARK: - 3D (SceneKit)

struct Scene3DPreview: NSViewRepresentable {
    let url: URL
    var onFailed: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(onFailed: onFailed) }

    func makeNSView(context: Context) -> SCNView {
        let v                        = SCNView(frame: .zero)
        v.backgroundColor            = NSColor.windowBackgroundColor
        v.allowsCameraControl        = true
        v.autoenablesDefaultLighting = true
        v.antialiasingMode           = .multisampling4X
        v.preferredFramesPerSecond   = 60

        let base = SCNScene()
        v.scene = base
        context.coordinator.scnView = v

        let capturedURL = url
        Task.detached(priority: .userInitiated) {
            let loaded = try? SCNScene(url: capturedURL, options: [
                SCNSceneSource.LoadingOption.convertToYUp: true
            ])
            await MainActor.run {
                if let scene = loaded, !scene.rootNode.childNodes.isEmpty {
                    for child in scene.rootNode.childNodes { base.rootNode.addChildNode(child) }
                } else {
                    context.coordinator.onFailed?()
                }
            }
        }
        return v
    }

    func updateNSView(_ nsView: SCNView, context: Context) {}

    final class Coordinator {
        weak var scnView: SCNView?
        var onFailed: (() -> Void)?
        init(onFailed: (() -> Void)?) { self.onFailed = onFailed }
    }
}

// MARK: - Generic fallback (unsupported format)

struct GenericPreview: View {
    let url: URL
    @State private var icon: NSImage?
    @State private var kindLabel = ""

    var body: some View {
        VStack(spacing: 14) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
            }
            Text(url.lastPathComponent)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 16)
            if !kindLabel.isEmpty {
                Text(kindLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text("Preview not available")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: url) {
            let path = url.path(percentEncoded: false)
            icon = await Task.detached(priority: .utility) {
                NSWorkspace.shared.icon(forFile: path)
            }.value
            let ext = url.pathExtension
            kindLabel = UTType(filenameExtension: ext)?.localizedDescription
                ?? (ext.isEmpty ? "" : "\(ext.uppercased()) File")
        }
    }
}

// MARK: - File Info Bar

struct FileInfoBar: View {
    let url: URL
    @State private var info: FileMetadata?
    @State private var chmodFeedback: String?

    var body: some View {
        Group {
            if let info {
                metadataContent(info)
            } else {
                HStack { Spacer(); ProgressView().controlSize(.mini); Spacer() }
                    .frame(height: 36)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task(id: url) { info = await FileMetadata.load(from: url) }
    }

    private func metadataContent(_ m: FileMetadata) -> some View {
        let rows: [(String, String)] = [
            ("Kind",         m.kind),
            m.size.map       { ("Size",       $0) },
            m.dimensions.map { ("Dimensions", $0) },
            m.duration.map   { ("Duration",   $0) },
            m.modified.map   { ("Modified",   $0) },
            m.created.map    { ("Created",    $0) },
            ("Path",         url.path(percentEncoded: false)),
        ].compactMap { $0 }

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 2) {
                    ForEach(rows, id: \.0) { label, value in
                        GridRow(alignment: .top) {
                            Text(label)
                                .gridColumnAlignment(.leading)
                                .foregroundStyle(.secondary)
                                .fixedSize()
                            Text(value)
                                .textSelection(.enabled)
                                .lineLimit(label == "Path" ? 3 : 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(.system(size: 10))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                if m.permissions != nil || m.owner != nil {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Permissions")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if let perms = m.permissions {
                            Text(perms)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        HStack(spacing: 4) {
                            if let owner = m.owner { Text(owner) }
                            if m.owner != nil && m.group != nil { Text(":") }
                            if let group = m.group { Text(group) }
                            if let octal = m.permissionsOctal {
                                Text("(\(octal))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 10))

                        HStack(spacing: 4) {
                            chmodButton(label: "+x") {
                                applyChmod(add: 0o111)
                            }
                            chmodButton(label: "-x") {
                                applyChmod(remove: 0o111)
                            }
                            chmodButton(label: "755") {
                                applyChmod(mode: 0o755)
                            }
                            chmodButton(label: "644") {
                                applyChmod(mode: 0o644)
                            }
                            chmodButton(label: "777") {
                                applyChmod(mode: 0o777)
                            }
                            chmodButton(label: "600") {
                                applyChmod(mode: 0o600)
                            }

                            if let feedback = chmodFeedback {
                                Text(feedback)
                                    .font(.system(size: 9))
                                    .foregroundStyle(feedback.hasPrefix("✓") ? .green : .red)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .font(.system(size: 10))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private func chmodButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func applyChmod(mode: UInt16) {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: mode],
                ofItemAtPath: url.path
            )
            showFeedback(success: true)
            Task { info = await FileMetadata.load(from: url) }
        } catch {
            showFeedback(success: false, error: error.localizedDescription)
        }
    }

    private func applyChmod(add bits: UInt16) {
        guard let current = info?.fileMode else { return }
        applyChmod(mode: current | bits)
    }

    private func applyChmod(remove bits: UInt16) {
        guard let current = info?.fileMode else { return }
        applyChmod(mode: current & ~bits)
    }

    private func showFeedback(success: Bool, error: String? = nil) {
        chmodFeedback = success ? "✓" : "✗ \(error ?? "Failed")"
        Task {
            try? await Task.sleep(for: .seconds(2))
            chmodFeedback = nil
        }
    }
}

// MARK: - FileMetadata

struct FileMetadata {
    let kind:             String
    let size:             String?
    let dimensions:       String?
    let duration:         String?
    let modified:         String?
    let created:          String?
    let permissions:      String?
    let owner:            String?
    let group:            String?
    let permissionsOctal: String?
    let fileMode:         UInt16?

    static func load(from url: URL) async -> FileMetadata {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey, .contentModificationDateKey,
            .creationDateKey, .localizedTypeDescriptionKey, .isDirectoryKey
        ]
        let rv  = try? url.resourceValues(forKeys: keys)
        let ext = url.pathExtension.lowercased()

        let kind = rv?.localizedTypeDescription
            ?? UTType(filenameExtension: ext)?.localizedDescription
            ?? (ext.isEmpty ? "Document" : "\(ext.uppercased()) File")

        let size: String? = {
            guard let bytes = rv?.fileSize, !(rv?.isDirectory ?? false) else { return nil }
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }()

        let modified = rv?.contentModificationDate.map { formatDate($0) }
        let created  = rv?.creationDate.map { formatDate($0) }

        // Image dimensions via ImageIO (reads header only, very fast)
        let isImageExt = imageExtensions.contains(ext)
        let dimensions: String? = await Task.detached(priority: .utility) { () -> String? in
            guard isImageExt else { return nil }
            guard let src   = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w     = props[kCGImagePropertyPixelWidth]  as? Int,
                  let h     = props[kCGImagePropertyPixelHeight] as? Int
            else { return nil }
            return "\(w) × \(h) px"
        }.value

        // Media duration via AVFoundation async API
        var duration: String? = nil
        if mediaExtensions.contains(ext) {
            let asset = AVURLAsset(url: url)
            if let dur = try? await asset.load(.duration) {
                let secs = CMTimeGetSeconds(dur)
                if secs.isFinite && secs > 0 { duration = formatDuration(secs) }
            }
        }

        // POSIX permissions
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let perms = attrs?[.posixPermissions] as? UInt16
        let owner = attrs?[.ownerAccountName] as? String
        let group = attrs?[.groupOwnerAccountName] as? String
        let permissions = perms.map { Self.permissionString(from: $0) }
        let permissionsOctal = perms.map { String(format: "%03o", $0 & 0o777) }

        return FileMetadata(
            kind: kind, size: size, dimensions: dimensions,
            duration: duration, modified: modified, created: created,
            permissions: permissions, owner: owner, group: group,
            permissionsOctal: permissionsOctal, fileMode: perms
        )
    }

    // MARK: Helpers

    private static func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today "     + date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "Yesterday " + date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func formatDuration(_ secs: Double) -> String {
        let t = Int(secs); let h = t / 3600; let m = (t % 3600) / 60; let s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    private static func permissionString(from mode: UInt16) -> String {
        let chars: [(UInt16, Character, Character)] = [
            (0o400, "r", "-"), (0o200, "w", "-"), (0o100, "x", "-"),
            (0o040, "r", "-"), (0o020, "w", "-"), (0o010, "x", "-"),
            (0o004, "r", "-"), (0o002, "w", "-"), (0o001, "x", "-"),
        ]
        return String(chars.map { mode & $0.0 != 0 ? $0.1 : $0.2 })
    }

    private static let imageExtensions: Set<String> = [
        "jpg","jpeg","png","gif","heic","heif","bmp","tiff","tif",
        "webp","ico","raw","cr2","cr3","nef","arw","dng","psd"
    ]
    private static let mediaExtensions: Set<String> = [
        "mp4","mov","avi","mkv","m4v","wmv","flv","webm","mpeg","mpg",
        "mp3","aac","flac","wav","aiff","aif","m4a","ogg","opus","caf"
    ]
}
