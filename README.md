# seeker | A lightweight n.b arpeggiation mod

I generally run small modular systems that are mostly controled by [n.b](https://llllllll.co/t/n-b-et-al-v0-1/60374)-powered norns scrips. This can be limiting when I want to use something that doesn't support n.b or isn't focused on modular integration. 

This mod lifts some of that burden as it runs in parallel with any script and enables two lanes of flexible arpeggiation which are great for filling out a track. Used in conjunction with [norns telexo](https://llllllll.co/t/telexo-norns-mod/67800/1) you can create compelling music to surround any of the more experimental sound-mangling norns scripts.

**Core Features**
- **Two arpeggiator lanes** that communicate directly with n.b
- Configurable playback patterns with **direction** and **step control** 
- Configurable chord selection across **multiple octaves** and **inversions**
- Configurable trigger modes taking either **gate input**, a **fixed trigger value**, or **weighted random** across note divisions
- Configurable **velocity curves** to add an organic feel to arpeggios

**Using It**
- Install [n.b](https://llllllll.co/t/n-b-et-al-v0-1/60374) if you don't already have it
- Plug any clock source into one of the Crow's input jacks
- Enter the associated `Seeker > Arpeggiator n` menu in `Params`to configure  