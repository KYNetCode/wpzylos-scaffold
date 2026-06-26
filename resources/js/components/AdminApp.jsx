import { useState, useEffect } from 'react';

export default function AdminApp() {
  const [activeTab, setActiveTab] = useState('general');
  const [darkMode, setDarkMode] = useState(false);
  const [message, setMessage] = useState('');
  const [settings, setSettings] = useState({
    name: '',
    apiKey: '',
    enabled: true,
  });

  useEffect(() => {
    if (window.myPluginData?.settings) {
      setSettings(prev => ({ ...prev, ...window.myPluginData.settings }));
    }
  }, []);

  const tabs = [
    { id: 'general', label: 'General' },
    { id: 'api', label: 'API' },
    { id: 'advanced', label: 'Advanced' },
  ];

  const save = () => {
    const formData = new FormData();
    formData.append('action', 'myplugin_save_settings');
    formData.append('nonce', window.myPluginData?.nonce || '');
    formData.append('settings', JSON.stringify(settings));

    fetch(window.ajaxurl, { method: 'POST', body: formData })
      .then(res => res.json())
      .then(data => {
        setMessage(data.success ? 'Settings saved!' : 'Error saving.');
        setTimeout(() => setMessage(''), 3000);
      });
  };

  const reset = () => setSettings({ name: '', apiKey: '', enabled: true });

  return (
    <div data-theme={darkMode ? 'dark' : 'light'}>
      <div className="flex justify-between items-center mb-4">
        <h1 className="text-xl font-bold">Settings</h1>
        <button
          className="__CSS_PREFIX__btn __CSS_PREFIX__btn-ghost __CSS_PREFIX__btn-circle"
          onClick={() => setDarkMode(!darkMode)}
          title={darkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode'}
        >
          {darkMode ? (
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 3v1m0 16v1m8.66-13.66l-.71.71M4.05 19.95l-.71.71M21 12h-1M4 12H3m16.66 7.66l-.71-.71M4.05 4.05l-.71-.71M16 12a4 4 0 11-8 0 4 4 0 018 0z" /></svg>
          ) : (
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20.354 15.354A9 9 0 018.646 3.646 9.005 9.005 0 0012 21a9.005 9.005 0 008.354-5.646z" /></svg>
          )}
        </button>
      </div>

      <div className="__CSS_PREFIX__tabs __CSS_PREFIX__tabs-bordered mb-6" role="tablist">
        {tabs.map(tab => (
          <a
            key={tab.id}
            role="tab"
            className={`__CSS_PREFIX__tab ${activeTab === tab.id ? '__CSS_PREFIX__tab-active' : ''}`}
            onClick={() => setActiveTab(tab.id)}
          >{tab.label}</a>
        ))}
      </div>

      {activeTab === 'general' && (
        <div className="__CSS_PREFIX__card __CSS_PREFIX__bg-base-100 __CSS_PREFIX__shadow-xl">
          <div className="__CSS_PREFIX__card-body">
            <h2 className="__CSS_PREFIX__card-title">General Settings</h2>

            <div className="__CSS_PREFIX__form-control w-full max-w-md mb-4">
              <label className="__CSS_PREFIX__label">
                <span className="__CSS_PREFIX__label-text">Plugin Name</span>
              </label>
              <input
                type="text"
                value={settings.name}
                onChange={e => setSettings({ ...settings, name: e.target.value })}
                className="__CSS_PREFIX__input __CSS_PREFIX__input-bordered w-full"
                placeholder="Enter plugin name"
              />
            </div>

            <div className="__CSS_PREFIX__form-control w-full max-w-md mb-4">
              <label className="__CSS_PREFIX__label">
                <span className="__CSS_PREFIX__label-text">API Key</span>
              </label>
              <input
                type="text"
                value={settings.apiKey}
                onChange={e => setSettings({ ...settings, apiKey: e.target.value })}
                className="__CSS_PREFIX__input __CSS_PREFIX__input-bordered w-full"
                placeholder="Enter API key"
              />
            </div>

            <div className="__CSS_PREFIX__form-control mb-6">
              <label className="__CSS_PREFIX__label cursor-pointer justify-start gap-4">
                <input
                  type="checkbox"
                  checked={settings.enabled}
                  onChange={e => setSettings({ ...settings, enabled: e.target.checked })}
                  className="__CSS_PREFIX__toggle __CSS_PREFIX__toggle-primary"
                />
                <span className="__CSS_PREFIX__label-text">Enable Plugin</span>
              </label>
            </div>

            <div className="flex gap-2">
              <button className="__CSS_PREFIX__btn __CSS_PREFIX__btn-primary" onClick={save}>Save Settings</button>
              <button className="__CSS_PREFIX__btn __CSS_PREFIX__btn-ghost" onClick={reset}>Reset</button>
            </div>

            {message && (
              <div className="__CSS_PREFIX__alert __CSS_PREFIX__alert-success mt-4">
                <span>{message}</span>
              </div>
            )}
          </div>
        </div>
      )}

      {activeTab === 'api' && (
        <div className="__CSS_PREFIX__card __CSS_PREFIX__bg-base-100 __CSS_PREFIX__shadow-xl">
          <div className="__CSS_PREFIX__card-body">
            <h2 className="__CSS_PREFIX__card-title">API Configuration</h2>
            <p className="text-sm opacity-70">Configure API endpoints and authentication.</p>
          </div>
        </div>
      )}
    </div>
  );
}
