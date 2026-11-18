# Use explicit intents without silent security downgrade

Freenet presents Hızlı Erişim and Dengeli Tünel as explicit user-selected intents because speed, IP visibility, and operator trust cannot be optimized simultaneously. An intent may retry equivalent engines, but it must never fall back to a weaker intent without informed user approval; this avoids showing a healthy connection after silently changing the user's protection contract.
