1. We are accepting all clients - no max clients or slots. no nothin
2. Not validating the server responses. Maybe you could do so with a salt or something idk
3. Not validating clients from incoming packets
4. To stop repeating the :receveive...() func, we just do a `until not ser_pkt` - but if a malicious user tried to send a bunch of `nil` packets, it would actually stop receiving packets until the next update (really bad if we only listen for packets at 20fps!)


Feature requests
- [ ] Write a full documentation
- [ ] Easier firewall rules
- [ ] Add a challenge / proper secure authentication (somewhat) - Maybe use signatures? salt?
- [ ] Attach custom properties to clients. Such as a player.
