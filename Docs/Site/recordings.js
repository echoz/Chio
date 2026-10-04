(() => {
  const recordings = [...document.querySelectorAll(".recording")];
  const links = [...document.querySelectorAll("[data-demo]")];
  const players = new Map();

  function mount(recording) {
    if (players.has(recording.id)) return;
    const container = recording.querySelector(".player");
    const preview = recording.querySelector(".recording-preview");
    const playButton = recording.querySelector(".play-recording");
    const message = recording.querySelector(".player-message");

    function showFallback() {
      preview.hidden = false;
      container.hidden = true;
      players.get(recording.id)?.dispose();
      players.delete(recording.id);
      playButton.textContent = "Retry playback";
      message.textContent = "Playback could not load. You can still download this recording and play it with asciinema.";
      message.hidden = false;
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
      player.addEventListener("error", showFallback);
    } catch {
      showFallback();
    }
  }

  function selectRecording() {
    const requestedID = location.hash.slice(1);
    const selected = recordings.find(recording => recording.id === requestedID) ?? recordings[0];
    for (const recording of recordings) {
      recording.hidden = recording !== selected;
      if (recording !== selected) players.get(recording.id)?.pause();
    }
    for (const link of links) {
      if (link.dataset.demo === selected.id) link.setAttribute("aria-current", "true");
      else link.removeAttribute("aria-current");
    }
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
