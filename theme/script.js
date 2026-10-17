for (const a of document.querySelectorAll("a[data-m]")) {
  const addr = [...a.dataset.m]
    .map((c) => String.fromCharCode(c.charCodeAt(0) - 1))
    .join("");

  a.href = "mailto:" + addr;
  a.textContent = addr;
}

/** Swaps a trailing `/index.html` for `/` */
const cleanPath = (path) => path.replace(/\/index\.html$/, "/");

// Change URLs in the address bar/history (without loading anything or adding entries)
history.replaceState(
  history.state,
  "",
  cleanPath(location.pathname) + location.search + location.hash,
);

// Rewrite links so hovering, copying a link, or clicking shows the clean URL
for (const a of document.querySelectorAll("a[href]:not([href^='#'])")) {
  const url = new URL(a.href);
  if (url.origin === location.origin) {
    url.pathname = cleanPath(url.pathname);
    a.href = url.href;
  }
}
