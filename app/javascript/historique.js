document.addEventListener("DOMContentLoaded", function() {
  const section   = document.getElementById('logs-section');
  if (!section) return;

  const csrfTag   = document.querySelector('meta[name="csrf-token"]');
  const csrfToken = csrfTag ? csrfTag.getAttribute('content') : null;

  // on bloque les submit à l'intérieur de la section
  section.addEventListener('submit', function(e){
    e.preventDefault();
    e.stopPropagation();
  }, true);

  async function postUndo(ids){
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
        template.content.querySelectorAll("turbo-stream").forEach((ts) => document.body.appendChild(ts));
      } else {
        // fallback
        location.reload();
      }
    } else {
      const txt = await resp.text();
      alert("Échec de l'undo (" + resp.status + ").\n" + txt);
    }
  }

  // ⚠️ on écoute tous les clics dans la section
  section.addEventListener("click", function(e) {
    const target = e.target;

    // 1) bouton "Tout cocher / décocher"
    if (target.id === "select-all-logs") {
      e.preventDefault();
      const checked = target.checked;
      section.querySelectorAll('.log-checkbox').forEach(cb => cb.checked = checked);
      return;
    }

    // 2) bouton "Undo la sélection"
    if (target.id === "bulk-undo-btn") {
      e.preventDefault();
      const ids = Array.from(section.querySelectorAll('.log-checkbox:checked')).map(cb => cb.value);
      if (ids.length === 0) {
        alert("Sélectionne au moins un log à annuler.");
        return;
      }
      postUndo(ids);
      return;
    }

    // 3) bouton "Undo" ligne par ligne
    if (target.classList.contains("single-undo-btn")) {
      e.preventDefault();
      const id = target.dataset.id;
      if (!id) return;
      postUndo([id]);
      return;
    }
  }, true);
});
