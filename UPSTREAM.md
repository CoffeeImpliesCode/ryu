# UPSTREAM

## Upstream identity

| Field | Value |
|---|---|
| Project | Ryu, IEEE-754 binary-to-decimal conversion |
| Repository | `https://github.com/ulfjack/ryu.git` |
| Pinned ref | Commit on `master`; no release tag is associated with this pin |
| Commit | `4c0618b0e44f7ef027ebae05d2cc7812048f7c8f` |
| Upstream version | `2.0`, declared in `CMakeLists.txt` |
| Native core licence | Apache-2.0 OR BSL-1.0 |

## Source acquisition

Obtained from a full clone of the canonical repository. The pinned tree's deterministic `git archive` SHA-256 is:

```
4218f6e9b0e98414919b53d27d17f1748ee11e28caf127da3a48117803790d13  -
```

Reproduce from a clone with:

```
git -C <clone> archive --format=tar 4c0618b0e44f7ef027ebae05d2cc7812048f7c8f | sha256sum
```

`UPSTREAM.sha256` contains 38 records: upstream files, six fork-authored test fixtures, and `translate.h`. It records the patched `ryu/ryu.h` digest beside upstream's digest. Removed upstream files: none.

## Upstream path changes

| Path | Difference |
|---|---|
| `ryu/ryu.h` | Replaces `<inttypes.h>` with `<stdint.h>` and adds the fork change notice. `uint32_t` remains declared; no API declaration or algorithm changes. |
| `.gitignore` | Appends `.zig-cache/` and `zig-out/`; upstream lines are unchanged. |
| `README.md` | Replaced by the fork README; upstream's original bytes are preserved as `README.upstream.md`. |

All other upstream files are retained without edits. `UPSTREAM.sha256` records the source, fixture, and licence inputs. Check the record from the repository root with:

```
sha256sum -c UPSTREAM.sha256
```
