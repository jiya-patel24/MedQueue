# MedQueue

**Live app:** https://jiya-patel24.github.io/MedQueue/
**Code:** https://github.com/jiya-patel24/MedQueue

## The annoyance
- People wait standing inside or outside crowded medical shops, often in a rush.
- I asked family members about everyday problems. My mom described having
  to stand in queues and crowds at medical shops.
- Idea: shops register, customers pick a nearby shop, get a token, and
  leave home only when their turn is close.

## The great part
- Per-shop token numbering: I found by testing a new shop that tokens were
  numbered across all shops (the first customer got #4), and fixed it.
- Shops can register themselves with a 6-digit PIN and then appear in a
  dropdown (grouped by area) for customers.

## The two testers
- Tester 1 (my mom, CS professor): suggested a dropdown of shops with their
  location, and that only the shop should see the staff side.
- Tester 2 (my aunt, software tester): suggested shops log their medicine
  stock so customers don't wait for a medicine that isn't available.
- What I changed: shops are now a dropdown grouped by area, and the staff
  side needs a shop-specific 6-digit PIN. While testing I also found that a
  customer was stuck once they had a token, so I added a Leave queue button.

## Security
- Tables have Row Level Security on with no policies, so the browser can only
  use the database through functions I wrote.
- Shop PINs are stored as bcrypt hashes. 5 wrong PINs lock that shop for 5 minutes.
- The customer dropdown reads a view that never includes the PIN hash.
- Every token has a random secret that only the customer who joined receives.
  Reading or cancelling a token needs both its id and its secret, so one person
  cannot cancel another person's spot by guessing ids.
- All user text is escaped before it is shown on the page.

## Known limits (things I chose not to build yet)
- No push notifications. The page checks every 5 seconds, and browsers slow
  down or pause background tabs, so a locked phone may miss the "Your turn"
  screen. I added a vibration and a tab-title change as a small help.
  Real push notifications are the proper fix.
- No rate limiting on joining or registering, so a script could spam a queue
  or fill the shop list with fake shops.
- Token numbers never reset, so they keep counting up each day.
- The staff PIN is kept in sessionStorage for the open tab so the page can
  refresh the queue.
- Medicine stock logging is not built. It is the next thing I would add.
- The design is simple on purpose. A cleaner, more polished UI is a good next step.

## Constraint (under 150 KB)
- One HTML file with inline CSS and JS, about 9 KB uncompressed, plus a small
  JSON response for the shop list.
- No framework, no library. Supabase is called with plain `fetch`, so I skipped
  the 100+ KB client library.
- The page polls every 5 seconds instead of using heavy realtime sockets.
- Measured in Chrome DevTools > Network with cache disabled: well under
  150 KB for both the customer page and the staff page.

## AI
- Used AI for code suggestions and to learn Supabase, which I had not used
  before. I learned the basics while building this.
