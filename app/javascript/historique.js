(function attachLogsPageHandlers() {
  function ready(fn) {
    if (document.readyState === "complete" || document.readyState === "interactive") {
      requestAnimationFrame(fn);
    } else {
      document.addEventListener("DOMContentLoaded", fn, { once: true });
    }
    document.addEventListener("turbo:load", fn, { once: true });
  }

  ready(function () {
    const section = document.getElementById("logs-section");
    if (!section) return;

    const csrfTag   = document.querySelector('meta[name="csrf-token"]');
    const csrfToken = csrfTag ? csrfTag.getAttribute("content") : null;

    // Bloque tout submit interne (pour éviter un submit fortuit dans la section)
    section.addEventListener("submit", function (e) {
      e.preventDefault();
      e.stopPropagation();
    }, true);

    async function postUndo(ids) {
      const resp = await fetch("/admin/merge_suggestions/bulk_undo", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ log_ids: ids })
      });

      if (resp.ok) {
        const ct = resp.headers.get("Content-Type") || "";
        if (ct.includes("text/vnd.turbo-stream.html")) {
          const html = await resp.text();
          const template = document.createElement("template");
          template.innerHTML = html.trim();
          template.content
            .querySelectorAll("turbo-stream")
            .forEach((ts) => document.body.appendChild(ts));
        } else {
          location.reload();
        }
      } else {
        const txt = await resp.text();
        alert("Échec de l'undo (" + resp.status + ").\n" + txt);
      }
    }

    // Délégation : un seul écouteur pour toute la section
    section.addEventListener("click", function (e) {
      const t = e.target;

      // 1) Tout cocher / décocher
      if (t.id === "select-all-logs") {
        e.preventDefault();
        const checked = t.checked;
        section.querySelectorAll(".log-checkbox").forEach(cb => cb.checked = checked);
        return;
      }

      // 2) Undo la sélection
      if (t.id === "bulk-undo-btn") {
        e.preventDefault();
        const ids = Array.from(section.querySelectorAll(".log-checkbox:checked")).map(cb => cb.value);
        if (ids.length === 0) {
          alert("Sélectionne au moins un log à annuler.");
          return;
        }
        postUndo(ids);
        return;
      }

      // 3) Undo ligne par ligne
      if (t.classList.contains("single-undo-btn")) {
        e.preventDefault();
        const id = t.dataset.id;
        if (!id) return;
        postUndo([id]);
        return;
      }
    }, true);

    // --- Recherche live dans le tableau ---
    const searchInput = section.querySelector("#log-search");
    if (searchInput) {
      const rows = () => section.querySelectorAll("tbody .log-row");
      const norm = (s) => (s || "").toString().toLowerCase().normalize("NFD").replace(/\p{Diacritic}/gu, "");

      searchInput.addEventListener("input", function () {
        const q = norm(this.value);
        rows().forEach(tr => {
          const src = tr.querySelector(".log-source")?.textContent || "";
          const tgt = tr.querySelector(".log-target")?.textContent || "";
          const when = tr.children[1]?.textContent || "";
          const hay = norm(src + " " + tgt + " " + when);
          tr.style.display = hay.includes(q) ? "" : "none";
        });
      });
    }
  });
})();
