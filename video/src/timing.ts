// The size and the length of the film: portrait 886 x 1920 (the size of an App Preview for the large iPhones),
// at 30 frames a second, the most that the App Store takes.
export const film = {width: 886, height: 1920, fps: 30, seconds: 7} as const;

// The store pictures are 1320 wide: the film draws at their scale, so a stroke or a badge looks the same on a phone.
export const K = film.width / 1320;
