## Possible vulnerabilites
1. [ ] We are accepting all clients - no max clients or slots. no nothin
2. [ ] Not validating the server responses. Maybe you could do so with a salt or something idk
3. [ ] Not validating clients from incoming packets
4. [X] To stop repeating the :receveive...() func, we just do a `until not ser_pkt` - but if a malicious user tried to send a bunch of `nil` packets, it would actually stop receiving packets until the next update (really bad if we only listen for packets at 20fps!)
5. [ ] When acknowledging reliable packets, we don't check if the client is the one. Same as IP Spoofing, really.
6. [ ] We are not validating for IP spoofing - should be done in `:_handlePacket()`


## Feature requests
- [ ] Add passwords 
- [ ] Write a full documentation
- [X] Add easier ways to deny/accept client connectiont requests
- [X] Add a limit to number of clients
- [ ] Easier firewall rules
- [ ] Handle packet duplication
- [ ] Handle packet corruption
- [ ] Handle packet reordering
- [ ] Add tests for bigger files (that require multiple packets).
- [X] Attach custom properties to clients. Such as a player. -> Can be done by client.player = Player(). Client is a reference in the hook.
- [X] Simulate network issues: latency, packet loss, noise... -> tc netem is good enough. Check test/units/poor_conditions_connections_spec.
- [X] Sending reliable packets - that will absolutely reach the player