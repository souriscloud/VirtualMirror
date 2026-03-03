# Acknowledgments

VirtualMirror builds on the work of several open-source projects and
reverse-engineering efforts. We gratefully acknowledge their contributions.

## FairPlay DRM Implementation

The FairPlay decryption code in `VirtualMirror/FairPlay/` originates from the
**playfair** library by EstebanKubata — a reverse-engineering of Apple's FairPlay
authentication protocol for AirPlay. The following files are derived from this work:

- `playfair.c` / `playfair.h`
- `omg_hax.c` / `omg_hax.h`
- `hand_garble.c`
- `sap_hash.c`
- `modified_md5.c`
- `fairplay_playfair.c` / `fairplay_playfair.h` (pre-computed response data)

This code has been incorporated into several open-source AirPlay receiver projects:

- **[shairplay](https://github.com/juhovh/shairplay)** by Juho Vaha-Herttua (LGPL-2.1)
- **[RPiPlay](https://github.com/FD-/RPiPlay)** by FD- (GPL-3.0)
- **[UxPlay](https://github.com/antimof/UxPlay)** by antimof (GPL-3.0)

## Protocol Reference

The AirPlay and RAOP protocol implementation in VirtualMirror was developed with
reference to:

- **[UxPlay](https://github.com/antimof/UxPlay)** — GPL-3.0 AirPlay mirror server
  for Unix. Feature flags, protocol handling patterns, and audio key derivation
  were informed by studying UxPlay's implementation.
- **[Unofficial AirPlay Protocol Specification](https://nto.github.io/AirPlay.html)**
  by nto — community-maintained protocol documentation.

## License

VirtualMirror is licensed under the GNU General Public License v3.0 (GPL-3.0),
consistent with the licenses of the upstream projects it incorporates.
See the [LICENSE](LICENSE) file for the full license text.
