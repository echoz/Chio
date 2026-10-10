(() => {
  const recordings = [...document.querySelectorAll(".recording")];
  const links = [...document.querySelectorAll("[data-demo]")];
  const categories = [...document.querySelectorAll(".demo-categories [data-category]")];
  const groups = [...document.querySelectorAll("[data-recording-group]")];
  const descriptions = [...document.querySelectorAll("[data-category-description]")];
  const themeSelect = document.querySelector("#gallery-theme");
  const players = new Map();
  const previewStates = new Map();

  function previewURL(recording) {
    return `recordings/themes/${recording.id}-${previewStates.get(recording.id).theme}.png`;
  }

  function themeName(theme) {
    return [...themeSelect.options].find(option => option.value === theme).textContent;
  }

  function describePreview(recording, playback = false) {
    const state = previewStates.get(recording.id);
    state.showPreview.hidden = !playback;
    recording.querySelector(".play-recording").hidden = playback;
    if (playback) {
      state.status.textContent = "Original terminal recording · theme choices change the static preview and run command only.";
    } else if (state.unavailable) {
      state.status.textContent = `Static preview unavailable · showing the original recording preview. The run command uses ${themeName(state.theme)}.`;
    } else {
      state.status.textContent = `Static preview · ${themeName(state.theme)} theme. The original recording keeps its recorded themes.`;
    }
  }

  function showPreview(recording) {
    const state = previewStates.get(recording.id);
    const container = recording.querySelector(".player");
    const restoreFocus = container.contains(document.activeElement) || document.activeElement === state.showPreview;
    const player = players.get(recording.id);
    player?.pause();
    recording.querySelector(".recording-preview").hidden = false;
    container.hidden = true;
    if (player) recording.querySelector(".play-recording").textContent = "Resume original recording";
    describePreview(recording);
    if (restoreFocus) themeSelect.focus({ preventScroll: true });
  }

  function selectTheme(recording) {
    const state = previewStates.get(recording.id);
    if (state.theme === themeSelect.value) return;
    state.theme = themeSelect.value;
    state.unavailable = false;
    state.image.setAttribute("src", previewURL(recording));
    const name = links.find(link => link.dataset.demo === recording.id).textContent;
    state.image.alt = `${name} in the ${themeName(state.theme)} theme (static preview).`;
    state.command.textContent = `${state.baseCommand} --theme ${state.theme}`;
    for (const snippet of state.snippets) {
      snippet.element.textContent = snippet.source.replaceAll(".chioTheme(.default)", `.chioTheme(.${state.theme})`);
    }
    showPreview(recording);
  }

  function mount(recording) {
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
      playButton.textContent = "Retry original recording";
      message.textContent = "The original recording could not load. You can still download it and play it with asciinema.";
      message.hidden = false;
      describePreview(recording);
      if (restoreFocus && !recording.hidden) playButton.focus({ preventScroll: true });
    }

    try {
      preview.hidden = true;
      container.hidden = false;
      message.hidden = true;
      describePreview(recording, true);
      const existing = players.get(recording.id);
      if (existing) {
        Promise.resolve(existing.play()).catch(() => {
          if (players.get(recording.id) === existing) showFallback(container.contains(document.activeElement));
        });
        existing.el.focus({ preventScroll: true });
        return;
      }
      const player = AsciinemaPlayer.create(recording.querySelector(".download").getAttribute("href"), container, {
        cols: Number(recording.dataset.cols),
        rows: Number(recording.dataset.rows),
        fit: "width",
        controls: true,
        autoplay: true,
        cursorMode: "steady",
      });
      players.set(recording.id, player);
      player.addEventListener("error", () => {
        if (players.get(recording.id) === player) showFallback(container.contains(document.activeElement));
      });
      player.el.focus({ preventScroll: true });
    } catch {
      showFallback(launchHadFocus);
    }
  }

  function revealSelectedLink() {
    const selectedLink = links.find(link => link.hasAttribute("aria-current"));
    if (!selectedLink) return;
    const selectedGroup = selectedLink.closest("[data-recording-group]");
    // Scroll only the horizontal chooser, preserving page position and focus.
    const left = selectedLink.offsetLeft;
    const right = left + selectedLink.offsetWidth;
    if (left < selectedGroup.scrollLeft) selectedGroup.scrollLeft = left;
    else if (right > selectedGroup.scrollLeft + selectedGroup.clientWidth) {
      selectedGroup.scrollLeft = right - selectedGroup.clientWidth;
    }
  }

  function selectRecording() {
    const requestedTheme = new URL(location.href).searchParams.get("theme");
    const hasKnownTheme = [...themeSelect.options].some(option => option.value === requestedTheme);
    themeSelect.value = hasKnownTheme ? requestedTheme : "default";
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
    for (const description of descriptions) {
      description.hidden = description.dataset.categoryDescription !== selected.dataset.category;
    }
    for (const category of categories) {
      if (category.dataset.category === selectedGroup.dataset.recordingGroup) category.setAttribute("aria-current", "true");
      else category.removeAttribute("aria-current");
    }
    if (hidesFocus) selectedLink.focus({ preventScroll: true });
    selectTheme(selected);
    revealSelectedLink();
  }

  // Keep the chooser in view; ordinary links still work without JavaScript and
  // modified clicks retain the browser's open-in-new-tab behavior.
  const relatedLinks = [...document.querySelectorAll("[data-catalog-link]")];
  for (const link of [...categories, ...links, ...relatedLinks]) {
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
    const controls = recording.querySelector(".theme-preview-controls");
    const image = recording.querySelector(".recording-image");
    const command = recording.querySelector(".recording-run code");
    const state = {
      image, command,
      theme: null,
      snippets: [...recording.querySelectorAll("[data-theme-code]")].map(element => ({ element, source: element.textContent })),
      status: controls.querySelector(".preview-status"),
      showPreview: controls.querySelector(".show-theme-preview"),
      originalSource: image.getAttribute("src"),
      originalAlt: image.alt,
      baseCommand: command.textContent.replace(/\s+--light\b/g, "").replace(/\s+--theme\s+\S+/g, ""),
      unavailable: false,
    };
    previewStates.set(recording.id, state);
    image.addEventListener("error", () => {
      if (image.getAttribute("src") !== previewURL(recording)) return;
      state.unavailable = true;
      image.setAttribute("src", state.originalSource);
      image.alt = state.originalAlt;
      describePreview(recording, !recording.querySelector(".player").hidden);
    });
    controls.hidden = false;
    state.showPreview.addEventListener("click", () => showPreview(recording));
    const playButton = recording.querySelector(".play-recording");
    playButton.hidden = false;
    playButton.addEventListener("click", () => mount(recording));
  }

  themeSelect.addEventListener("change", () => {
    const url = new URL(location.href);
    if (themeSelect.value === "default") url.searchParams.delete("theme");
    else url.searchParams.set("theme", themeSelect.value);
    history.pushState(null, "", url);
    selectRecording();
  });
  document.querySelector(".gallery-theme-controls").hidden = false;
  selectRecording();

  window.addEventListener("popstate", selectRecording);
  window.addEventListener("hashchange", selectRecording);
  window.addEventListener("resize", revealSelectedLink);
})();
