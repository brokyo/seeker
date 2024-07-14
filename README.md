# seeker | A lightweight n.b arpeggiation mod

I generally run small modular systems that are mostly controled by [n.b](https://llllllll.co/t/n-b-et-al-v0-1/60374)-powered norns scrips. This approach can be limiting when I want to use something that doesn't support n.b or isn't focused on modular integration.

This mod is intended to lift some of that burden. As a mod, it runs in parallel with any script and enables two lanes of flexible arpeggiation which are great for filling out a track. Used in conjunction with [norns telexo](https://llllllll.co/t/telexo-norns-mod/67800/1) you can create compelling music to surround any of the more experimental sound-mangling norns scripts in just 6hp.

**To Install**
`;install https://github.com/brokyo/seeker`

**Requirements**
- Norns
- Crow
- N.b
- Clock source

**Core Features**
- **Two arpeggiator lanes** that communicate directly with n.b
- Playback patterns with **direction** and **step control** 
- Chord selection across **multiple octaves** and **inversions**
- Note division trigger modes taking either **gate input**, **fixed trigger value**, or **weighted random**
- **Velocity curves** to add an organic feel to arpeggios

**Using It**
- [If you don't already have it] Install [n.b](https://llllllll.co/t/n-b-et-al-v0-1/60374)
- Install this mod with `;install https://github.com/brokyo/seeker`
- Enable the mod [following the instructions on Monome's site](https://monome.org/docs/norns/mods/)
- Plug any clock source into one of the Crow's input jacks
- Enter the associated `Seeker > Arpeggiator n` menu in `Params`to configure