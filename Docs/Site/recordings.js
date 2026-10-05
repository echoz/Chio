(() => {
  const recordings = [...document.querySelectorAll(".recording")];
  const links = [...document.querySelectorAll("[data-demo]")];
  const categories = [...document.querySelectorAll("[data-category]")];
  const groups = [...document.querySelectorAll("[data-recording-group]")];
  const players = new Map();

  function mount(recording) {
    if (players.has(recording.id)) return;
    const container = recording.querySelector(".player");
    const preview = recording.querySelector(".recording-preview");
    const playButton = recording.querySelector(".play-recording");
    const message = recording.querySelector(".player-message");
    const launchHadFocus = document.activeElement === playButton;

    function showFallback(restoreFocus) {
      preview.hidden = false;
      container.hidden = true;
      players.get(recording.id)?.dispose();
      players.delete(recording.id);
      playButton.textContent = "Retry playback";
      message.textContent = "Playback could not load. You can still download this recording and play it with asciinema.";
      message.hidden = false;
      if (restoreFocus && !recording.hidden) playButton.focus({ preventScroll: true });
    }

    try {
      preview.hidden = true;
      container.hidden = false;
      message.hidden = true;
      const player = AsciinemaPlayer.create(recording.querySelector(".download").getAttribute("href"), container, {
        cols: Number(recording.dataset.cols),
        rows: Number(recording.dataset.rows),
        fit: "width",
        controls: true,
        autoplay: true,
        cursorMode: "steady",
      });
      players.set(recording.id, player);
      player.addEventListener("error", () => showFallback(container.contains(document.activeElement)));
      player.el.focus({ preventScroll: true });
    } catch {
      showFallback(launchHadFocus);
    }
  }

  function selectRecording() {
    const requestedID = location.hash.slice(1);
    const selected = recordings.find(recording => recording.id === requestedID) ?? recordings[0];
    const selectedLink = links.find(link => link.dataset.demo === selected.id);
    const selectedGroup = selectedLink.closest("[data-recording-group]");
    const activeElement = document.activeElement;
    const hidesFocus = recordings.some(recording => recording !== selected && recording.contains(activeElement))
      || groups.some(group => group !== selectedGroup && group.contains(activeElement));
    for (const recording of recordings) {
      recording.hidden = recording !== selected;
      if (recording !== selected) players.get(recording.id)?.pause();
    }
    for (const link of links) {
      if (link.dataset.demo === selected.id) link.setAttribute("aria-current", "true");
      else link.removeAttribute("aria-current");
    }
    for (const group of groups) group.hidden = group !== selectedGroup;
    for (const category of categories) {
      if (category.dataset.category === selectedGroup.dataset.recordingGroup) category.setAttribute("aria-current", "true");
      else category.removeAttribute("aria-current");
    }
    if (hidesFocus) selectedLink.focus({ preventScroll: true });

    // Reveal the active example in the narrow horizontal menu without moving the page.
    const left = selectedLink.offsetLeft;
    const right = left + selectedLink.offsetWidth;
    if (left < selectedGroup.scrollLeft) selectedGroup.scrollLeft = left;
    else if (right > selectedGroup.scrollLeft + selectedGroup.clientWidth) {
      selectedGroup.scrollLeft = right - selectedGroup.clientWidth;
    }
  }

  // Keep the chooser in view; ordinary links still work without JavaScript and
  // modified clicks retain the browser's open-in-new-tab behavior.
  for (const link of [...categories, ...links]) {
    link.addEventListener("click", event => {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      const hash = link.getAttribute("href");
      if (location.hash !== hash) history.pushState(null, "", hash);
      selectRecording();
    });
  }

  // Keep the screenshot until explicit playback. NPT posters in player 3.17
  // can leave its first seek with stale replay indices and an incomplete frame.
  for (const recording of recordings) {
    const playButton = recording.querySelector(".play-recording");
    playButton.hidden = false;
    playButton.addEventListener("click", () => mount(recording));
  }

  window.addEventListener("hashchange", selectRecording);
  selectRecording();
})();
