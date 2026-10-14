for (const a of document.querySelectorAll("a[data-m]")) {
  const addr = [...a.dataset.m]
    .map((c) => String.fromCharCode(c.charCodeAt(0) - 1))
    .join("");

  a.href = "mailto:" + addr;
  a.textContent = addr;
}
