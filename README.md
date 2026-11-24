# OPUlation

Two phones may only share a secret once they have courted like fruit flies.

**Play:** https://linglab.org/opulation/ (GitHub Pages from `main`, root). Use two phones, both online. One chooses *Court* (he sends), the other *Be courted* (she receives). There is no passphrase: the courtship itself is the pairing. An iPhone app on the same protocol is in `ios/`; it pairs with the page and, between two iPhones, also links directly over Multipeer (Bluetooth and peer-to-peer Wi-Fi, the AirDrop machinery).

## How to court

1. Two phones, one quiet room, volume up.
2. The sender picks **♂ Court**, the receiver **♀ Be courted**.
3. She starts first, allows the microphone and turns the brightness up. Her face appears: it holds her key and a room code.
4. He starts, allows the camera and microphone, and fills his camera with her face until it locks.
5. Keep the phones close and quiet. His phone sings about four seconds of courtship song; hers judges it.
6. If she accepts, a private chat opens on both: notes, photos, files. Leaving ends it; nothing is kept.

These steps live behind the **How to mate** button; a **Now** bar says what to do at each moment. His phone shows a male *Drosophila* courting her and his male-connectome courtship circuit; hers shows her FlyWire auditory network hearing his song.

## The pairing

It is Bluetooth's "numeric comparison" pairing, with the comparing done by flies over channels a remote attacker can't reach (`js/pair.js`):

| Stage | What the flies do | What the phones do |
|---|---|---|
| **Orient** | He sees her. | Her screen shows her face, a fruit fly's head from the front. Her compound eyes carry 41 bytes: a version, which links she can use, an 8-byte room code and her X25519 public key; 520 facets, Reed-Solomon coded, found by four ink dots. His camera reads it, so he has her real key: nothing on the network touched it. |
| **Tap** | He approaches and taps her. | Both phones join the room on a small relay (a Cloudflare Worker, `worker/`), and he sends his public key. The relay is not trusted: whoever runs it could swap his key for theirs. |
| **Sing** | He extends one wing and sings: sine song, then four pulse trains. | The song is the check code: the first 16 bytes of SHA-512 of the room and both public keys, as 64 inter-pulse intervals of 30, 36, 42 or 48 ms. Played three octaves up for phone speakers; she decodes the intervals and replays the true-pitch song into her ears. He sings in bouts until she answers. |
| **She decides** | She slows and opens, or kicks and runs. Silently. | She computes the song from the keys she actually received. If anyone swapped his key, the song he really sings doesn't match, and she kicks. Her FlyWire song pathway must reach threshold too. Up to 4 wrong notes out of 64 are forgiven, for a noisy room. Her answer is sealed with keys only she could make from her face's key, so he knows it is hers. |
| **Mate** | Copulation. | An end-to-end encrypted session opens (ChaCha20-Poly1305, one key and counter per direction, replays refused). On the web the phones then try a direct WebRTC data channel, whose setup travels sealed, so its DTLS fingerprints are bound to the courtship; if the networks won't connect directly within a few seconds, the session simply stays on the relay, still end-to-end encrypted. Between two iPhones the link is Multipeer from the start. Photos, files and notes, both ways, as many as you like. |

Every primitive (X25519, SHA-512, ChaCha20-Poly1305) exists in both libsodium and Apple's CryptoKit; `data/vectors2.json` pins every derived byte so the web page and the iPhone app pair with each other.

## Her brain, and his

- **Her ears and song pathway** are [FlyHarp](https://linglab.org/flyharp/)'s Tonnectome network: 4,222 neurons and 1.35 M synapses from FlyWire v783 (Johnston's organ, AMMC, saddle, wedge, AVLP and on), with FlyHarp's antenna filterbank and rate dynamics. It is not trained or fit; wiring and transmitter signs are measured, gains and time constants set by hand.
- **OPUlation runs it in integers** (Q16 fixed point, `js/female.js`). Every constant that needs floating point is frozen in `data/female-model.json` by `tools/make-model.mjs`, so two phones, or Swift and JavaScript, compute the same brain bit for bit (`data/vectors.json`).
- **She is individual.** Each neuron's gain varies by up to ±12.5%, drawn from a seed that both phones derive from their shared X25519 secret. His phone runs her too, and shows what she should be feeling while he sings.
- **Her receptivity** reads the mean activity of the 32 cells in the AVLP, PVLP and wedge that respond most to pulse song. vpoEN, the AVLP neuron that responds to song and drives vaginal plate opening in real flies, is in the network and marked. In this untrained model it barely responds, so it is shown but not used.
- **His eye** is FlyHarp's optic lobe: the flyvis connectome-constrained model (Lappalainen et al. 2024; 45,669 neurons, 65 cell types, 721 ommatidia), run in a worker (`js/fly/`, copied from FlyHarp). While his camera reads her face, the same view is sampled onto his 721 facets and drawn as four lenses: photoreceptors, ON (Mi1, Tm3), OFF (Tm1, 2, 4, 9) and T4/T5 motion. His eye resolves about 5° per facet, so the phone camera does the actual reading; his optic lobe shows what a fly makes of the same view. Its frontal OFF and motion activity drives LC10a in his courtship circuit, standing in for the real LC10a, which lies beyond the model.
- **His circuit is from a male connectome**: 978 neurons and 23,964 connections (synapse counts of 5 or more) cut from Janelia's male CNS connectome (v0.9; brain and nerve cord of one male, Berg et al. 2025), drawn where their cell bodies sit. It runs from LC10a (275 cells, seeing her) and vAB3 (tasting her) through P1 (148 cells) and the song descending neurons (pIP10, pMP2, pIP9) to the nerve cord's song premotor network (vPR6 and dPR1 for pulse, TN1a for sine, vMS12, and the types Lillvis et al. 2024 traced in MANC) and 67 wing motor neurons, plus the 380 neurons that link successive stages most strongly. Signs come from predicted transmitters (ACh +, GABA and glutamate −), except vAB3, whose glutamate excites P1 in recordings (Clowney et al. 2015). Dynamics are a plain rate model with one hand-set gain and time constant, as in FlyHarp. In it, seeing or tasting her wakes P1, P1 drives pIP10, and pIP10 drives the song premotor and wing motor neurons, all through the connectome's own wiring. Two things are imposed: his eye's frontal output drives LC10a, and the song's rhythm (each pulse, each hum) comes from the key and is fed into the pulse and sine premotor neurons, scaled by pIP10's activity. A rate model can't generate the rhythm itself. `tools/male-cns/` rebuilds it from the public release.

## Security, honestly

- **What protects you is the air.** Her face can only be read by a camera pointed at her screen, and his song can only be heard by a microphone near his phone. A remote attacker (including whoever runs the relay) can swap keys on the network, but then the song she expects is not the one he sings, and she kicks. The check is 128 bits compared note by note with up to 4 wrong notes forgiven, about 100 bits of margin.
- **What it doesn't stop:** someone in the room, close enough to see her screen and sing to her phone, is courting her too. Same as Bluetooth pairing: proximity is the trust.
- **The relay sees** that two phones met in a room, when, and how many bytes passed. It can't read or alter them. It keeps nothing.
- Not audited.

## Files

```
index.html  css/opulation.css
js/pair.js      the pairing: her face, his hello, keys, the song as check code, sealed sessions
js/pipe.js      how sealed frames travel: the relay, then a direct WebRTC channel; the channel the chat runs on
js/link.js      the nest: files, photos and notes in chunks, with flow control
js/flycode.js   her face as a visual code: draw + read at any rotation, Reed-Solomon
js/song.js      the song: tag <-> intervals, the ideal antenna frames, her listener, on-air render, pulse detector
js/female.js    the FlyWire auditory network in Q16 integers, with a seeded personality
js/male.js      his courtship-song circuit, from the male CNS connectome (data/male.json + male.bin)
js/eye.js       his optic lobe (FlyHarp's flyvis model in js/fly/), fed by the camera
js/app.js       the page
worker/         the relay: a Durable Object per room, two sockets, frames passed through untouched
ios/            the iPhone app (Swift): same protocol, plus Multipeer
data/           ear.json + ear.bin (from FlyHarp), female-model.json, vectors.json, vectors2.json, male.json + male.bin (Janelia male CNS v0.9, CC BY 4.0)
tools/          relay-dev.mjs (the relay, locally), make-model.mjs, male-cns/, test*.mjs, pair-test.py
```

**Tests:** `npm install && npm test` runs the pairing protocol and its vectors (including a man in the middle swapping keys), her face under perspective, blur and noise, her brain's determinism and its agreement with the check code, the song through simulated echo, his connectome circuit, a whole ritual through camera and room, and the relay. `tools/pair-test.py` runs the real page twice in headless Chrome through a local relay (`node tools/relay-dev.mjs`): her face feeds his camera, his song her ears, until the chat opens, notes and a file cross both ways, and his leaving ends it on hers. With `NODIRECT=1` it checks the relay-only path.

**Relay setup (once):** Cloudflare dashboard › Workers & Pages › Create › Import a repository › Opulation, root directory `worker`. Each push then redeploys it at `opulation-relay.samuelling.workers.dev`.
