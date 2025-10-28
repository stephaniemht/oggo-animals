document.addEventListener("DOMContentLoaded", function() {
  const section   = document.getElementById('logs-section');
  if (!section) return;

  const selectAll = section.querySelector('#select-all-logs');
  const bulkBtn   = section.querySelector('#bulk-undo-btn');
  const csrfTag   = document.querySelector('meta[name="csrf-token"]');
  const csrfToken = csrfTag ? csrfTag.getAttribute('content') : null;

  section.addEventListener('submit', function(e){
    e.preventDefault();
    e.stopPropagation();
  }, true);

  function shieldClick(handler){
    return function(e){
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();
      handler.call(this, e);
    }
  }

  if (selectAll) {
    selectAll.addEventListener('change', function(){
      section.querySelectorAll('.log-checkbox').forEach(cb => cb.checked = selectAll.checked);
    });
  }

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
        location.reload();
      }
    } else {
      const txt = await resp.text();
      alert("Échec de l'undo (" + resp.status + ").\n" + txt);
    }
  }

  if (bulkBtn) {
    bulkBtn.addEventListener('click', shieldClick(async function(){
      const ids = Array.from(section.querySelectorAll('.log-checkbox:checked')).map(cb => cb.value);
      if (ids.length === 0) {
        alert("Sélectionne au moins un log à annuler.");
        return;
      }
      await postUndo(ids);
    }));
  }

  section.querySelectorAll('.single-undo-btn').forEach(btn => {
    btn.addEventListener('click', shieldClick(async function(){
      await postUndo([this.dataset.id]);
    }));
  });
});
