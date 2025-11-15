import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

// Hide loading screen once React app loads
const loadingElement = document.getElementById('loading');
if (loadingElement) {
  loadingElement.style.display = 'none';
}

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);

root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);