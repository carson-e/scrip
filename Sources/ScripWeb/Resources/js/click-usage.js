function labelOf(el) {
  return `${el.innerText || ""} ${el.getAttribute("aria-label") || ""} ${el.getAttribute("title") || ""}`
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

function isUsageLabel(t) {
  return t === "usage" || t.startsWith("usage ") || t.endsWith(" usage");
}

function usageTab() {
  const nodes = [
    ...document.querySelectorAll('button, a, [role="tab"], [role="button"], [role="menuitem"]'),
  ];
  return nodes.find((el) => {
    const t = labelOf(el);
    if (!t || t.includes("settings")) return false;
    return isUsageLabel(t);
  }) || null;
}

function clickUsageTab() {
  const usage = usageTab();
  if (!usage) return false;
  usage.click();
  return true;
}

function clickSettingsControl() {
  const nodes = [
    ...document.querySelectorAll('button, a, [role="tab"], [role="button"], [role="menuitem"]'),
  ];
  const exact = nodes.find((el) => {
    const t = labelOf(el);
    return t === "settings" || t === "setting";
  });
  if (exact) {
    exact.click();
    return true;
  }
  const labeled = nodes.find((el) => {
    const t = (el.getAttribute("aria-label") || el.getAttribute("title") || "").toLowerCase().trim();
    return t === "settings" || t === "open settings" || t === "account settings";
  });
  if (labeled) {
    labeled.click();
    return true;
  }
  const usageHref = [...document.querySelectorAll("a[href]")].find((a) => {
    const href = (a.getAttribute("href") || "").toLowerCase();
    return /settings\/usage|dashboard\/usage|\/usage\/?$/.test(href);
  });
  if (usageHref) {
    usageHref.click();
    return true;
  }
  const settingsHref = [...document.querySelectorAll("a[href]")].find((a) => {
    const href = (a.getAttribute("href") || "").toLowerCase();
    return href.includes("/settings") && !href.includes("privacy");
  });
  if (settingsHref) {
    settingsHref.click();
    return true;
  }
  return false;
}

function openUsageView() {
  if (clickUsageTab()) return "usage";
  if (clickSettingsControl()) return "settings";
  return "missing";
}

function remountUsage() {
  const usage = usageTab();
  if (!usage) return "missing";
  const container =
    usage.closest('[role="tablist"], nav, [role="navigation"], aside, menu') ||
    usage.parentElement;
  const siblings = [
    ...(container
      ? container.querySelectorAll('button, a, [role="tab"], [role="button"], [role="menuitem"]')
      : []),
  ];
  const other = siblings.find((el) => {
    if (el === usage) return false;
    const t = labelOf(el);
    if (!t || isUsageLabel(t)) return false;
    if (/sign out|log out|logout|delete|disconnect|revoke/i.test(t)) return false;
    return true;
  });
  const selected =
    usage.getAttribute("aria-selected") === "true" ||
    usage.getAttribute("data-state") === "active" ||
    usage.getAttribute("aria-current") === "page";
  if (other && selected) {
    other.click();
    return "switched";
  }
  usage.click();
  return "clicked";
}
