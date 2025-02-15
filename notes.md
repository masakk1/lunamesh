## Possible vulnerabilites
1. We are accepting all clients - no max clients or slots. no nothin
2. Not validating the server responses. Maybe you could do so with a salt or something idk
3. Not validating clients from incoming packets
4. To stop repeating the :receveive...() func, we just do a `until not ser_pkt` - but if a malicious user tried to send a bunch of `nil` packets, it would actually stop receiving packets until the next update (really bad if we only listen for packets at 20fps!)
5. When acknowledging reliable packets, we don't check if the client is the one.
6. We are not validating for IP spoofing - should be done in `:_handlePacket()`
7. Handle duplicate packets (specially reliable acks)


## Feature requests
- [ ] Write a full documentation
- [ ] Easier firewall rules
- [ ] Add a challenge / proper secure authentication (somewhat) - Maybe use signatures? salt?
- [ ] Attach custom properties to clients. Such as a player.
- [ ] Simulate network issues: latency, packet loss, noise...
- [ ] Sending safe packets - that will absolutely reach the player
