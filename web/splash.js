// Fades out the HTML splash in index.html once Flutter has drawn its first
// frame. A separate file (not inline) so the CSP can keep script-src 'self'.
window.addEventListener('flutter-first-frame', function () {
  var splash = document.getElementById('splash');
  if (!splash) return;
  splash.classList.add('done');
  setTimeout(function () { splash.remove(); }, 250);
});
