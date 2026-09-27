{{flutter_js}}
{{flutter_build_config}}

// Browser application only: do not register a service worker or install prompt.
_flutter.loader.load({
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    document.getElementById('loading')?.remove();
  }
});
