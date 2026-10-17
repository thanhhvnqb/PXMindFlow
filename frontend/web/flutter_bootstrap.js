{{flutter_js}}
{{flutter_build_config}}

const status = document.getElementById('startup-status');
const message = document.getElementById('startup-message');
const retry = document.getElementById('startup-retry');
let firstFrame = false;

function showStartupFailure() {
  if (firstFrame) return;
  status.hidden = false;
  message.textContent = 'MindFlow could not finish loading. Check your connection and try again.';
  retry.hidden = false;
}

window.addEventListener('flutter-first-frame', () => {
  firstFrame = true;
  status.remove();
});
window.addEventListener('error', showStartupFailure);
window.addEventListener('unhandledrejection', showStartupFailure);
retry.addEventListener('click', () => window.location.reload());
setTimeout(() => {
  if (!firstFrame) {
    message.textContent = 'MindFlow is still loading. Check your connection or try again.';
    retry.hidden = false;
  }
}, 30000);

_flutter.loader.load({
  config: {canvasKitBaseUrl: 'canvaskit/'},
  onEntrypointLoaded: async (engineInitializer) => {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
    } catch (error) {
      console.error('MindFlow startup failed', error);
      showStartupFailure();
    }
  },
}).catch(showStartupFailure);
