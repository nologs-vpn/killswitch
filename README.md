# VPN Kill Switch for Linux, Windows and MacOS

Running a VPN without a Kill switch is not recommended. 
While most VPN providers out there implement their own Kill switch services - we, the minimalists, the ones who like to [create custom VPN servers](https://nologs-vpn.com), are often left to wonder for solutions as many of the official packages do not implement such a thing.

VPN connections drop at any time and sometimes drop quite often, a time when your real ip address, dns and other sensitive data is free to leak outside of the tunnel. 
By using a VPN Kill Switch you basically kill any other traffic outside of the tunnel. We have a more extensive article on this subject if you want to find more about [how a Kill Switch works](http://localhost:8000/vpn-killswitch-what-is-do-you-need). 

This repo is still a work in progress and I welcome everyone to participate with ideas, feedback or code.

Shameless plug

### Build your own no logs secure VPN
This project is part of the [nologs-vpn](https://nologs-vpn.com) project. nologs-vpn allows you to create VPN servers hosted on your own VM server. For a small fee our service creates the server, installs the desired VPN service and generates client config so you can connect. In just 5 minutes you can have your own, private and secure, VPN server that has no logs, no backdoors and is powered by tested, open-source software.