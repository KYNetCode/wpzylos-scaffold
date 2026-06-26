import '../css/admin.css';
import { createApp } from 'vue';
import AdminApp from './components/AdminApp.vue';

// Mount Vue app when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  const mountEl = document.getElementById('my-plugin-admin-app');
  if (mountEl) {
    const app = createApp(AdminApp);
    app.mount(mountEl);
  }
});

// --- React alternative (uncomment if using React instead of Vue) ---
// import React from 'react';
// import { createRoot } from 'react-dom/client';
// import AdminApp from './components/AdminApp.jsx';
//
// document.addEventListener('DOMContentLoaded', () => {
//   const mountEl = document.getElementById('my-plugin-admin-app');
//   if (mountEl) {
//     createRoot(mountEl).render(<AdminApp />);
//   }
// });
