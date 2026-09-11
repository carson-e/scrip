import Foundation

enum ScrapeScripts {
    static func extract(hints: [String], keywords: [String]) -> String {
        """
        \(load("extract"))
        extractUsage(\(jsArray(hints)), \(jsArray(keywords)));
        """
    }

    static var clickUsage: String {
        """
        \(load("click-usage"))
        clickUsageTab();
        """
    }

    static var remountUsage: String {
        """
        \(load("click-usage"))
        remountUsage();
        """
    }

    static var openUsageView: String {
        """
        \(load("click-usage"))
        openUsageView();
        """
    }

    private static func load(_ name: String) -> String {
        for url in candidateURLs(name) {
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                return text
            }
        }
        return fallback(name)
    }

    private static func candidateURLs(_ name: String) -> [URL] {
        let file = "\(name).js"
        var urls: [URL] = []
        if let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "js") {
            urls.append(url)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "js") {
            urls.append(url)
        }
        let roots: [URL] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(),
        ].compactMap { $0 }
        let relatives = [
            "js/\(file)",
            "Scrip_ScripWeb.bundle/js/\(file)",
            "Scrip_ScripWeb.bundle/\(file)",
        ]
        let fm = FileManager.default
        for root in roots {
            for rel in relatives {
                let url = root.appendingPathComponent(rel)
                if fm.fileExists(atPath: url.path) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    private static func jsArray(_ values: [String]) -> String {
        let encoded = values
            .map { $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
            .map { "\"\($0)\"" }
            .joined(separator: ",")
        return "[\(encoded)]"
    }

    private static func fallback(_ name: String) -> String {
        switch name {
        case "extract":
            """
            function extractUsage(hints, keywords) {
              const parts = [];
              let n = 0;
              if (document.body) {
                const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                while (walk.nextNode()) {
                  const t = (walk.currentNode.nodeValue || "").replace(/\\s+/g, " ").trim();
                  if (!t) continue;
                  parts.push(t);
                  n += t.length;
                  if (n > 8000) break;
                }
              }
              const text = parts.join("\\n");
              const blocked = /Sorry, you have been blocked|Just a moment|Attention Required|cf-browser-verification/i.test(text);
              const lowerText = text.toLowerCase();
              const hasLoginHints = (hints || []).some((h) => lowerText.includes(String(h).toLowerCase()));
              const loggedIn = text.length > 40 && !blocked && !hasLoginHints;
              const lines = text.split("\\n").map((s) => s.trim()).filter(Boolean).slice(0, 40);
              return JSON.stringify({
                loggedIn, blocked, url: location.href, lines, bars: [], text: text.slice(0, 12000),
                candidates: { percents: [], dollars: [], resets: [], labeledRows: lines }
              });
            }
            """
        case "click-usage":
            """
            function clickUsageTab() { return false; }
            function remountUsage() { return "missing"; }
            function openUsageView() { return "missing"; }
            """
        default:
            "null"
        }
    }
}
