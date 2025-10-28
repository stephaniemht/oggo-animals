// app/javascript/bulk_selection.js
function setupBulkSelection() {
  const form = document.getElementById('bulk-form');
  if (!form) return;

  const getChecks = () => Array.from(form.querySelectorAll('.row-check'));
  const submit    = form.querySelector('#bulk-submit');
  const countEl   = form.querySelector('#sel-count');
  const checkAll  = form.querySelector('#check-all');

  function refresh() {
    const n = getChecks().filter(c => c.checked).length;
    if (submit)  submit.disabled = (n === 0);
    if (countEl) countEl.textContent = n + (n > 1 ? " sélections" : " sélection");
  }

  // Nettoie puis (re)attache
  getChecks().forEach(c => {
    c.removeEventListener('change', refresh);
    c.addEventListener('change', refresh);
  });

  if (checkAll) {
    const onToggleAll = () => {
      getChecks().forEach(c => { c.checked = checkAll.checked; });
      refresh();
    };
    checkAll.removeEventListener('change', onToggleAll);
    checkAll.addEventListener('change', onToggleAll);
  }

  // init
  refresh();
}

// Écoute plusieurs événements pour être sûr (Turbo + vanilla)
window.addEventListener('turbo:load', setupBulkSelection);
document.addEventListener('turbo:render', setupBulkSelection);
document.addEventListener('DOMContentLoaded', setupBulkSelection);
