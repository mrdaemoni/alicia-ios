# Archetype Presence Lab evidence

Captured on the iPhone 17 simulator from the DEBUG-only Motion Lab on
2026-08-16. Simulator imagery and resource samples are review evidence, not
final device visual or performance approval.

## Six geometric families

![Beatrice, Ariadne, Psyche, Daimon, Muse, and Musubi](six-archetypes.png)

All six captures use LISTENING at 72% ATTENTION. From left to right, top then
bottom: Beatrice drift, Ariadne weave, Psyche depth, Daimon singular, Muse
bloom, and Musubi knot.

## Motion and Reduce Motion

![Two Muse animation frames one second apart](motion-frames.png)

The two frames differ after excluding the simulator status area:

- Frame A pixel MD5: `6bc32fbd59df9757d6f7e78950fd147d`
- Frame B pixel MD5: `b8bb422d93d8d2691cd6e32abe3516b0`

![Muse intentional Reduce Motion still](reduce-motion.png)

Two Reduce Motion captures one second apart produced the same cropped pixel
MD5: `da5948cbbacb0260d3b2ea8c641f8a31`.

## Bounds and resource evidence

![Audit at zero and full attention](attention-audits.png)

At both 0% and 100% ATTENTION, AUDIT ALL passed 72 combinations: six voices,
three states, and four representative phases. The lowest visible-point
fraction was 99%, and every sampled point was finite.

The maximum-density Psyche field at 100% ATTENTION was sampled five times on
the simulator after launch. The host process used 5.4%, 10.4%, 8.7%, 7.5%,
and 6.9% CPU, with resident memory between 210,880 and 211,360 KB. This is a
relative simulator check only. Pandaiux remains the required performance gate
before promotion.
