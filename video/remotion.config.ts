import {existsSync} from 'node:fs';
import {Config} from '@remotion/cli/config';

Config.setVideoImageFormat('jpeg');
Config.setOverwriteOutput(true);

// Some sandboxed environments (e.g. Claude Code on the web) block Remotion's
// headless-browser download but ship a Chromium at this path. Elsewhere,
// Remotion downloads and manages its own browser as usual.
const preinstalledChromium = '/opt/pw-browsers/chromium';
if (existsSync(preinstalledChromium)) {
  Config.setBrowserExecutable(preinstalledChromium);
  Config.setChromeMode('chrome-for-testing');
}
