import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import AdminPage from './components/AdminPage';
import './index.css';

const rootElement = document.getElementById('root');
if (!rootElement) {
  throw new Error("Could not find root element to mount to");
}

const root = ReactDOM.createRoot(rootElement);
const normalizedPath = window.location.pathname.replace(/\/+$/, '') || '/';
const isAdminRoute = normalizedPath === '/admin';

root.render(
  <React.StrictMode>
    {isAdminRoute ? <AdminPage /> : <App />}
  </React.StrictMode>
);
