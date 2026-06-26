<template>
  <div :data-theme="darkMode ? 'dark' : 'light'">
    <div class="flex justify-between items-center mb-4">
      <h1 class="text-xl font-bold">Settings</h1>
      <button
        class="__CSS_PREFIX__btn __CSS_PREFIX__btn-ghost __CSS_PREFIX__btn-circle"
        @click="toggleDarkMode"
        :title="darkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode'"
      >
        <svg v-if="darkMode" xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m8.66-13.66l-.71.71M4.05 19.95l-.71.71M21 12h-1M4 12H3m16.66 7.66l-.71-.71M4.05 4.05l-.71-.71M16 12a4 4 0 11-8 0 4 4 0 018 0z" /></svg>
        <svg v-else xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.354 15.354A9 9 0 018.646 3.646 9.005 9.005 0 0012 21a9.005 9.005 0 008.354-5.646z" /></svg>
      </button>
    </div>

    <div class="__CSS_PREFIX__tabs __CSS_PREFIX__tabs-bordered mb-6">
      <a
        v-for="tab in tabs"
        :key="tab.id"
        class="__CSS_PREFIX__tab"
        :class="{ '__CSS_PREFIX__tab-active': activeTab === tab.id }"
        @click="activeTab = tab.id"
      >{{ tab.label }}</a>
    </div>

    <div v-if="activeTab === 'general'" class="__CSS_PREFIX__card __CSS_PREFIX__bg-base-100 __CSS_PREFIX__shadow-xl">
      <div class="__CSS_PREFIX__card-body">
        <h2 class="__CSS_PREFIX__card-title">General Settings</h2>
        
        <div class="__CSS_PREFIX__form-control w-full max-w-md mb-4">
          <label class="__CSS_PREFIX__label">
            <span class="__CSS_PREFIX__label-text">Plugin Name</span>
          </label>
          <input
            v-model="settings.name"
            type="text"
            class="__CSS_PREFIX__input __CSS_PREFIX__input-bordered w-full"
            placeholder="Enter plugin name"
          />
        </div>

        <div class="__CSS_PREFIX__form-control w-full max-w-md mb-4">
          <label class="__CSS_PREFIX__label">
            <span class="__CSS_PREFIX__label-text">API Key</span>
          </label>
          <input
            v-model="settings.apiKey"
            type="text"
            class="__CSS_PREFIX__input __CSS_PREFIX__input-bordered w-full"
            placeholder="Enter API key"
          />
        </div>

        <div class="__CSS_PREFIX__form-control mb-6">
          <label class="__CSS_PREFIX__label cursor-pointer justify-start gap-4">
            <input v-model="settings.enabled" type="checkbox" class="__CSS_PREFIX__toggle __CSS_PREFIX__toggle-primary" />
            <span class="__CSS_PREFIX__label-text">Enable Plugin</span>
          </label>
        </div>

        <div class="flex gap-2">
          <button class="__CSS_PREFIX__btn __CSS_PREFIX__btn-primary" @click="save">Save Settings</button>
          <button class="__CSS_PREFIX__btn __CSS_PREFIX__btn-ghost" @click="reset">Reset</button>
        </div>

        <div v-if="message" class="__CSS_PREFIX__alert __CSS_PREFIX__alert-success mt-4">
          <span>{{ message }}</span>
        </div>
      </div>
    </div>

    <div v-if="activeTab === 'api'" class="__CSS_PREFIX__card __CSS_PREFIX__bg-base-100 __CSS_PREFIX__shadow-xl">
      <div class="__CSS_PREFIX__card-body">
        <h2 class="__CSS_PREFIX__card-title">API Configuration</h2>
        <p class="text-sm opacity-70">Configure API endpoints and authentication.</p>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'AdminApp',
  data() {
    return {
      activeTab: 'general',
      darkMode: false,
      message: '',
      tabs: [
        { id: 'general', label: 'General' },
        { id: 'api', label: 'API' },
        { id: 'advanced', label: 'Advanced' },
      ],
      settings: {
        name: '',
        apiKey: '',
        enabled: true,
      },
    };
  },
  mounted() {
    // Load settings from WordPress localized data
    if (window.myPluginData) {
      this.settings = { ...this.settings, ...window.myPluginData.settings };
    }
  },
  methods: {
    toggleDarkMode() {
      this.darkMode = !this.darkMode;
    },
    save() {
      // WordPress AJAX save
      const formData = new FormData();
      formData.append('action', 'myplugin_save_settings');
      formData.append('nonce', window.myPluginData?.nonce || '');
      formData.append('settings', JSON.stringify(this.settings));

      fetch(window.ajaxurl, { method: 'POST', body: formData })
        .then(res => res.json())
        .then(data => {
          this.message = data.success ? 'Settings saved!' : 'Error saving.';
          setTimeout(() => { this.message = ''; }, 3000);
        });
    },
    reset() {
      this.settings = { name: '', apiKey: '', enabled: true };
    },
  },
};
</script>
