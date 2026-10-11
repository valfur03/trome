# Reads the host and the app token of the production server from Server.xcconfig, for the scripts that call it.
# Source it after setting config to the path of the file and defining say <line> [status], which prints the line
# and exits; it sets host and token, or says what is wrong with the file. It prints neither value.

file=ios/Config/Server.xcconfig

# The value of a setting as Xcode reads it: // starts a comment, the spaces around the value go, the last line wins.
setting() {
    sed -n -e 's/\r$//' -e 's|//.*||' -e "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$config" | tail -n 1 | sed 's/[[:space:]]*$//'
}

[ -f "$config" ] || say "No $file: make it as step 4.2 of the release guide says (cp -n ios/Config/Server.example.xcconfig $file), put the host and the app token in it, then run this again."

host=$(setting TRAIN_SERVER_HOST)
token=$(setting TRAIN_SERVER_APP_TOKEN)

[ -n "$host" ] || say "No host in $file: put the host of the production server after TRAIN_SERVER_HOST =, then run this again."
case $host in
    *[!A-Za-z0-9.-]* | .* | -*)
        say "TRAIN_SERVER_HOST in $file is not a host: write only the host, with no https:// and no path, then run this again." ;;
    *staging*)
        say "TRAIN_SERVER_HOST in $file is the staging server: put the host of the production server, then run this again." ;;
esac
[ -n "$token" ] || say "No app token in $file: put the APP_TOKEN of the production server after TRAIN_SERVER_APP_TOKEN =, then run this again."
