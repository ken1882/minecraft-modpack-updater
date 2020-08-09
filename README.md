# Minecraft Modpack Updater
Used in my custom modpack - Modern Fantasy
Using GoogleDrive APIs as remote to check updates

## Installation
### Windows
Download in [release page](https://github.com/ken1882/minecraft-modpack-updater/releases) and extract to modpack's minecraft folder

### Linux / Mac
Run the source directly
1. Install Ruby
2. Clone repo and cd to the directory
3. Install bundler: `gem install bundler`
4. Install dependencies: `bundler install`
5. Copy `updater.rb`, `libsodium.so`, `mf_modpack_updater.so` and `cacert.pem` to modpack's minecraft folder
6. Run with `ruby updater.rb`
