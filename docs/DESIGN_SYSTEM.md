# Mukafaah design system (`packages/mk_ui`)

Brand from the Mukafaah identity: **purple `#2C123F`**, **yellow `#FBD404`**, white; rounded shapes; gold coin with the Mukafaah mark; yellow squiggles on purple.

- **Tokens** (`tokens.dart`): colours (brand, neutrals, semantic, program types), spacing 4–48, radii 10/14/20/28/pill, shadows (soft, lifted, glow), icon sizes, motion (140/240/420 ms, count 900 ms, stagger 55 ms; ease-out-cubic enter).
- **Theme** (`theme.dart`): Material 3 via `material_ui`, Arabic-first (RTL), custom buttons, inputs, cards, nav bar/rail, sheets, snackbars, chips.
- **Motion** (`motion.dart`): `MkEntrance` (fade + rise, staggered), `MkPressable` (press scale), `AnimatedPoints` (count-up; display only), `MkSuccessMark` (drawn check), `MkFloat` (ambient float). Respects "reduce motion".
- **Components**: `MkButton` (primary/accent/secondary/ghost/danger, loading), `MkCard`, `MkWalletCard`, `MkStatTile`, `MkProgramBadge`, `MkIconTile`, `MkMonogram`, `MkSectionHeader`, `MkLogo`, `MkCoin`, `MkSwirlBackground`, `MkQr` (branded QR with coin centre, high error correction), `MkPhoneField` (+961), `MkOtpField`, `MkKeypad`, `MkPinDots`, `MkToast`, `MkEmptyState`, `MkErrorState`, `MkSkeleton`, `MkSuccessView`, `showMkSheet`.

Recommended design tool: **Figma** for the source of truth (components mirror these tokens 1:1), with Claude's Design artifacts for quick mockups. Original logo files (SVG/AI) are needed to replace the traced PNGs in `assets/brand`.
