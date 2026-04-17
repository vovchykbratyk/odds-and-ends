# SMB mounter / automounter (macOS only)

This is a super lightweight little automounter utility that keeps a SMB mounted on macOS.  You should only have to set it up once; or at least once per share.

## How to use

* download the files
* edit the obvious parts in the files and filenames
    * i.e., swap out your actual username where it says `username`
    * default paths are suggestions, edit them to what you want, just ensure you're consistent across both files
* Assuming the default paths,
    * `remount-smb.sh` goes in `~/Applications`
        * do a `chmod +x ~/Applications/remount-smb.sh`
    * `org.username.remount-smb.plist` goes in `~/Library/LaunchAgents`
* Start the service
    ```bash
    launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/org.username.remount-smb.plist 2>/dev/null

    launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.username.remount-smb.plist

    launchctl enable gui/$(id -u)/org.username.remount-smb

    launchctl kickstart -k gui/$(id -u)/org.username.remount-smb

## Notes

This is what I use to basically make my home SMB share a cloud-like, available-anywhere resource.

The script is quiet on temporary failures that are usually associated with changing/updating network states, i.e. close the lid at home, open it at a coffee shop, turn on Tailscale or whatever tunneling protocol you use to access the SMB resource - just let it do its thing and it'll hook up when the path comes up.

You *will* need to have credentials already in your keychain as that's what `/sbin/mount_smbfs` looks in.