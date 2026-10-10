/// The wallpaper of every picture of the app that a `make` command takes: the docs pictures and the store pictures.
/// This is the only place that names it, so that all the pictures agree, and a new pick is one edit here.
/// `ios/scripts/wallpaper.sh` reads the id below from this file: keep it on one line, in quotes.
///
/// It is Apple's "fluidity.three", a wallpaper of iOS that the Simulator draws,
/// named by its id in the wallpaper gallery.
/// Its licence is Apple's, as a part of iOS: the repo holds no image file of it, only its id.
/// `make simulator-wallpaper` sets it once on the shared Simulator, which keeps it:
/// a picture command only checks that it is there.
enum Wallpaper {
    static let galleryID = "com.apple.MercuryPoster:fluidity.three"
}
