Replay-Kit
==========

Replay Web Archives on Desktop.

<div style="width:40%; margin: 0;">

![screeshot 1](assets/Screenshot-2026-06-23-1.png)

</div>
</br>


## Summary

Replay-Kit is a simple tool that allows users to browse Web Archives offline.
Build for Gnome desktop environment, and is capable of replaying **Wacz archives only**. Warc, Har, MHTML or other web archive formats may be added in the future.
Makes use of [replayweb.page](https://replayweb.page/docs/embedding/) and WebKit.

</br>

## Install

At the moment no pre-binaries or flathub package are provided. 

You can either compile & install on your desktop or as flatpak.

### Compile & Install on host

To compile and install on desktop `make` and `valac` compiler are used. 

```bash
# Compile application
make

# Run application without installing 
./build/replay-kit

# Or by providing path to wacz archive 
./build/replay-kit ~/Download/example.wacz

# Install application
sudo make install
```

### Build & Install flatpak

To build flatpak `make`, `flatpak` and `flatpak-builder` are used.
 
```bash
# Build and install flatpak  
make flatpak-install 

# Run flatpak  
flatpak run io.gitlab.vgmkr.replay-kit
```
