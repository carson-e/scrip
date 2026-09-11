function extractUsage(hints, keywords) {
  const norm = (s) =>
    (s || "")
      .replace(/[\u00a0\u202f\u2007\u2009]/g, " ")
      .replace(/％/g, "%");

  const fromShadows = [];
  const portals = document.querySelectorAll(
    "dialog, [role='dialog'], [role='tabpanel'], [data-state='open'], [data-radix-portal]"
  );
  for (const el of portals) {
    fromShadows.push(norm(el.innerText || ""));
    if (el.shadowRoot) fromShadows.push(norm(el.shadowRoot.innerText || ""));
  }
  for (const frame of document.querySelectorAll("iframe")) {
    try {
      const t = frame.contentDocument && frame.contentDocument.body && frame.contentDocument.body.innerText;
      if (t) fromShadows.push(norm(t));
    } catch (e) {}
  }

  const body = (() => {
    const root = document.body;
    if (!root) return "";
    const parts = [];
    let n = 0;
    const walk = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    while (walk.nextNode()) {
      const t = (walk.currentNode.nodeValue || "").replace(/\s+/g, " ").trim();
      if (!t) continue;
      parts.push(t);
      n += t.length;
      if (n > 8000) break;
    }
    return norm(parts.join("\n"));
  })();
  const grokPanel = (keywords || []).some((k) => String(k).toLowerCase().includes("supergrok"))
    ? (() => {
        const nodes = [
          ...portals,
          ...document.querySelectorAll("aside, section"),
        ];
        const matches = nodes
          .map((el) => norm(el.innerText || ""))
          .filter((t) => t.length > 0 && t.length < 2000 && /Weekly SuperGrok/i.test(t) && /%/.test(t))
          .sort((a, b) => a.length - b.length);
        return matches[0] || "";
      })()
    : "";
  const text = [grokPanel, ...fromShadows, body].filter(Boolean).join("\n");
  const blocked = /Sorry, you have been blocked|Just a moment|Attention Required|cf-browser-verification/i.test(text);
  const lowerText = text.toLowerCase();
  const hasUsageText = /%\s*used|weekly supergrok|current session|included usage/i.test(text);
  const hasLoginHints = (hints || []).some((h) => lowerText.includes(String(h).toLowerCase()));
  const loggedIn = !blocked && (hasUsageText || (text.length > 40 && !hasLoginHints));
  const dateRangeRe =
    /\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:,\s*\d{4})?\s*[-–—]\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:,\s*\d{4})?/ig;
  const rangeHits = (text.match(dateRangeRe) || []).map((s) => s.replace(/\s+/g, " ").trim());
  const tableRows = [...document.querySelectorAll("tr, [role='row']")].slice(0, 24).map((el) =>
    norm(el.innerText).replace(/\s+/g, " ").trim()
  );
  const lines = [...text.split("\n"), ...tableRows].map((s) => s.trim()).filter((s) => {
    if (!s || s.length > 180) return false;
    if (/\d+\s*%/.test(s) || /\d+\s*\/\s*\d+/.test(s) || /\$[\d.]+/.test(s)) return true;
    if (/\bin\s+\d+\s*(hr|hour|min|day)/i.test(s)) return true;
    if (/\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}\b/i.test(s) && /[-–—]/.test(s)) return true;
    if (/\d{1,2}\/\d{1,2}\/\d{2,4}/.test(s)) return true;
    const lower = s.toLowerCase();
    return (keywords || []).some((k) => lower.includes(String(k).toLowerCase()));
  });
  const uniqueLines = [...new Set([...rangeHits, ...lines])].slice(0, 60);
  const percents = [];
  const seen = new Set();
  const addPercent = (label, value) => {
    if (!Number.isFinite(value) || seen.has(label)) return;
    seen.add(label);
    percents.push({ label: label.slice(0, 80), value });
  };
  for (const line of uniqueLines) {
    const match = line.match(/(\d+(?:\.\d+)?)\s*%/);
    if (match) addPercent(line, parseFloat(match[1]));
  }
  const usedMatch = text.match(/(\d+(?:\.\d+)?)\s*%\s*used/i);
  if (usedMatch) addPercent(usedMatch[0], parseFloat(usedMatch[1]));
  const dollars = uniqueLines.flatMap((line) => {
    const match = line.match(/\$(\d+(?:\.\d+)?)/);
    return match ? [{ label: line.slice(0, 80), value: parseFloat(match[1]) }] : [];
  });
  const resets = [...new Set([
    ...uniqueLines.filter((line) => /reset/i.test(line)),
    ...rangeHits,
  ])].slice(0, 12);
  const bars = [...document.querySelectorAll('[role="progressbar"], progress')].map((el) => {
    const label = el.getAttribute("aria-label")
      || el.parentElement?.innerText?.split("\n").map((s) => s.trim()).filter(Boolean)[0]
      || "";
    const value = parseFloat(el.getAttribute("aria-valuenow") || el.getAttribute("value") || "");
    const max = parseFloat(el.getAttribute("aria-valuemax") || el.getAttribute("max") || "");
    return {
      label: label.slice(0, 80),
      value: Number.isFinite(value) ? value : null,
      max: Number.isFinite(max) ? max : null
    };
  });
  return JSON.stringify({
    loggedIn,
    blocked,
    url: location.href,
    lines: uniqueLines,
    bars: bars.slice(0, 12),
    text: text.slice(0, 12000),
    candidates: {
      percents: percents.slice(0, 20),
      dollars: dollars.slice(0, 20),
      resets,
      labeledRows: uniqueLines
    }
  });
}
