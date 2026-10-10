import {Config} from '@remotion/cli/config';

Config.setEntryPoint('src/index.ts');
// One browser tab per render: a render shares the Mac with the other heavy jobs (see README.md, "Render").
Config.setConcurrency(1);
// A loaded Mac makes the first frame slow: wait up to 2 minutes for it, not 30 seconds.
Config.setDelayRenderTimeoutInMilliseconds(120000);
Config.setVideoImageFormat('jpeg');
Config.setCodec('h264');
Config.setAskAIEnabled(false);
