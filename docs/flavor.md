# Flavor

The Sound Lab's **Flavor** page makes a synth patch from fourteen knobs and five switches named for what you hear: Lean ↔ Beefy, Silky ↔ Gritty, Polite ↔ Farty. It sits beside the Synth page, which has every setting; Flavor has a few strong ones. What it makes is an ordinary `AKPatch`, so it plays, bakes and opens in the Synth page like any other.

How the controls were chosen and tuned is in `docs/plans/flavor-tab.md`.

## The page

- **Two-way knobs** (top row) rest in the middle and turn either way toward one of their two words.
- **Add knobs** (lower row) rest at zero and only turn up.
- **Switches** are beside the add knobs. Minor is greyed out until Note ↔ Chord is past 0.6, where the third it changes comes in.
- **Knobs:** drag up or right to turn one up (Shift for fine steps), roll the wheel, or use the arrow keys. Double-click returns a knob to rest. Hover for what it does.
- **Toolbar:** name the sound; **Randomise** (a new sound: most knobs near rest, a few pushed far); **Mutate** (a near neighbour; the slider sets how far); **Undo**; **Reset** (the base sound); a menu of sounds you saved; **Save**; **Open in Synth**.
- **Play:** click the keyboard, use the computer keys (Z S X … / Q 2 W …), or tick **MIDI input** for a MIDI keyboard. The scope shows the output, and the **Limiter** light comes on when the sound reaches the limiter's ceiling.

Every move rebuilds the same patch in place, the way an edit on the Synth page does, so the sound changes as you turn. Playing live needs the native core, as on the Synth page.

When Stiff ↔ Slinky leaves zero the sound plays one note at a time, and a note by the keyboard says so.

## Saving and reopening

**Save** writes `res://audio/patches/<name>.tres`. The control positions are stored in the patch (as metadata), so choosing it from the page's menu puts every knob back.

**Open in Synth** hands a copy to the Synth page for fine-tuning. That is one way: once a patch is edited there, its stored positions describe the sound before those edits. It still opens on the Flavor page, with a notice, as that earlier sound rebuilt from the knobs.

## Loudness

Some combinations are much louder than others. When the controls settle, the page measures the sound and sets one fixed gain so it lands within 3 LU of the base sound. Nothing reacts to the signal, so playing dynamics are untouched, and a quiet sound is never raised so far that its peaks hit the limiter: short plucked sounds stay a little quieter. With the native core this happens whenever the controls settle; without it, on Save.

Every Flavor patch ends in a limiter at −1 dBFS, so no combination can clip.

## MIDI controller knobs

Tick **MIDI input**, right-click a knob, choose **Learn MIDI controller**, and turn a knob on your controller. From then on that hardware knob moves it; a small dot marks a linked knob.

- A hardware knob that is somewhere else than the knob on screen does nothing until it reaches the on-screen position, so nothing jumps.
- On a two-way knob the controller's middle is rest.
- Links are kept in the editor's settings, not in the patch, and work in the editor only.

## From code

```gdscript
var patch := AKFlavor.build({lean_beefy = 0.6, shut_quack = 1.0, pump = true})
AKFlavor.level(patch)                       # even out its loudness
var settings := AKFlavor.settings_of(patch) # what it was built from
var edited := AKFlavor.is_stale(patch)      # changed since?
var next := AKFlavor.mutate(settings, 42)   # a near neighbour
```

`AKFlavor.KNOBS` and `AKFlavor.SWITCHES` list the controls. Knobs take −1 .. 1 (two-way) or 0 .. 1; switches take `true` or `false`; anything left out is at rest.

To hear a control's range without the editor:

```
godot --headless --path . -s res://addons/audio_kit/tools/flavor_listen.gd -- --only lean_beefy --out out/flavor
```
