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
- Being able to add multiple shops along with their Pin codes so that they appear as a dropdown to the customers.

## The two testers
- Tester 1 (my mom, CS professor): suggested a dropdown of shops with their
  location, and that only the shop should see the staff side.
- Tester 2 (my aunt, software tester): suggested shops log their medicine
  stock so customers don't wait for a medicine that isn't available.
- What I changed: shops are now a dropdown grouped by area, and the staff
  side needs a shop-specific 6-digit PIN. While testing I also found that a
  customer was stuck once they had a token, so I added a Leave queue button.

## Features not added yet but are a good idea
- I did not build the medicine stock feature; it is the next thing I would add.
- Frontend is pretty decent right now. I personally think it needs to be a little more impressive and UI friendly.

## Constraint (under 150 KB)
- First load: 3.3 kB transferred (8.0 kB uncompressed, 1 request), measured
  in Chrome DevTools > Network with cache disabled.
- No framework, no library. One HTML file with inline CSS/JS.
- Supabase is called with plain `fetch`, so I skipped the 100+ KB client library.
- Page checks for new data every 5 sec instead of heavy realtime sockets.
- Observed 3.9 kB for the customer page and 3.6 kB for the shop staff page.

## AI
- Used AI for code suggestions and to learn Supabase, which I had not used
  before. I learned the basics while building this. 
