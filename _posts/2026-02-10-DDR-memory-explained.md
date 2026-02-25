---
layout: post
title: "DDR memory explained"
date: 2026-02-09
---

## Introduction

The reason why I wrote this blog is I found a lot of articles and paper in DRAM area tend to use a simplified DRAM model and propose their design over this conceptual model. Honestly speaking, there is no problem with it since academic research and idea brainstorm does not need to consider many complex real-world problems(also, DRAM vendor are always slience on whats going on irl so we don't know anything). However, I also realized all the articles and papers in DRAM research does not have a complete background introduction that can actually give a full picture of what is DDR DRAM and what's the pitfalls and constraints in DRAM design. In this case, I am going to talk some of them.

This blog will mainly focus on regular DDR memory, specifically, DDR4. So yeah, no DDR5 or some crazy GDDR or HBM architecture. However, both of them are also interesting to discover and I'll post some papers which I found super helpful.

This blog will also be a periodic update one, since DRAM vendor are so slient so there are always something new waiting for people to discover. All updated content will be placed in Updates section

## Index
1. [DRAM conceptual model](#dram-conceptual-model)
2. [Memory controller and DDR commands](#memory-controller-and-ddr-commands)
3. [DDR commands timing](#ddr-commands-timing)
4. [DRAM hierarchy](#dram-hierarchy)
5. [Conceptual model for subarray](#conceptual-model-for-subarray)
6. [Break the conceptual model for subarray](#break-the-conceptual-model-for-subarray)
7. [Sense Amplifier](#sense-amplifier)
8. DRAM repair
9. DRAM chip-level reverse engineering
10. tbd...
11. Updates


## DRAM conceptual model
From the perspective of software programmer, DRAM is just a super long 1D array. If you are into the UNIX philosophy, there's no difference with DRAM or SSD or HDD since they can all being "mmaped" and do read() and write() over it. However, such simplified 1D array is just an illusion given by cache hierarchy since they are cleaver(or big) enough to know the next piece of data CPU want to grab for most of the time. Unfortunantly, cache hierarchy cannot make 100% prediction on future, and when it predict failed, requests needs to goes into the next level. It can be anything connected to NoC, e.g. UART/RDMA/GPU, but for the most of time, it goes into DRAM.

DRAM has a big difference compare with DFF or SRAM array. DFF and SRAM are all digital signal holder and it's easy to send a request in clock cycle 0 and get the data back in clock cycle 1. It's easy to just open an access transistor and pump the data in/out of it. For DRAM, which operate in capacitor for the purpose of storage density and cost control, doesn't have the self-amplification ability as CMOS. It's also more complex to access data from DRAM compare with access data from DFF/SRAM array. 

A single bit storage logic in DRAM would looks like this:

[PICTURE OF 1T1C cell]

Bits(1/0) are stored inside the capacitor in the form of charge. Once the access transistor closed(connected), the charge inside capacitor will be shared with circuit outside through Bitline. Observing the voltage change after connected the access transistor, we can determine if the data inside contain 1 or 0.

Write procedure to a single cell is also easy. Simply drive the correspond bitline with correct voltage can solve the problem. If we want to write 0 then we drive the bitline with a voltage smaller than Vref so capacitor will share the charge to reach equalibrium. If we want to write 1 then we drive bitline with a voltage higher than Vref so it will charge capacitor to reach the equalibrium. If we want to store the bits inside we just need to open(disconnect) the access transisotr, and charge will be kept inside the capacitor.

Above is the operation to access one single bits in DRAM. However, to access a large amount of data and send them to CPU cache subsystem would require a lot of extra jobs. A typical access sequence to DRAM cell is split into following phases:

```c
ACTIVATE -> READ/WRITE -> PRECHARGE
```

This sequence can be applied on DRAM cell array which looks like this:

[PICTURE OF DRAM CELL ARRAY]

During the ACTIVATION phase, the access transistor for a whole row of cell will connect its correspond capacitor with the bitline next to it. Bitlines are all connected with a row buffer which will "buffer" the data in capacitor and they are ready for future READ/WRITE.

During READ/WRITE phase, CPU can read/write from/to the row buffer, and row buffer will reflect the changes made by CPU into those connected capacitor.

During PRECHARGE phase, access transistor will close and buffer will be set into "default" state and ready for next ACTIVATION.

This is a conceptual model of how DRAM works internally.

## Memory controller and DDR commands
As all kinds of storage devices(from DFF array to HDD disk), they are designed as a command receiver which basically receive the requests and bring back data. The way we access DFF array is by pumping it with clock signal and assert R/W port in correct time. For DRAM, we do not have such convenient way to access. Instead, we use specific command to tell DRAM when to do what. These commands is called DDR command.

This can be a weird thing to think about. The way we access memory in C looks like:

```c
int a = *(int*)addr;
```

And even if we write above code into assembly, it would looks like this:

```
ld $t0, 0($a3)
```

There's never any "DDR" command on example above, so who use DDR command?

The answer is memory controller.

Appearantly DRAM itself is not smart enough to understand when CPU said "Please give me data in address 0xdeadbeef". They are optimized for holding as much data as possible and cheap as possible. Typically they do not have the ability to run logics on it. It's relying on CPU to tell what to do next. The command it received from CPU is called DDR command and it looks like this:

```
ACT row x, READ column y, WRITE column z, PRE(precharge) row x
```

Precharge can be understood as "close" a row. This is not true as we went further but for now lets assume it's true.

There's a small components in CPU side which translate regular memory read/write requests into those sequence of DDR command.

[DIE SHOT OF MC]

DDR commands also have different execution time. They are written in JEDEC DDR standard and they are always constant. For example, ACT tooks 15ns to execute and RD/WR only takes 4ns. Memory controller should handle both the next command and the timing to issue the next command, since DRAM is too "stupid" to figure out what's going on.

The way MC issue DDR commands is like a queue. MC will post the command type and when to issue info into a queue, and issuer will send the command out when it's the time. For example, if it's clock 8 right now and I want to issue an RD in clock 12, I will push my request into the queue, and this request will goes out when it's 12 in clock.

It's kinda weird to find each command in DRAM subsystem have a thing called timing. In regular FPGA programming, if we are access one module from another, we only needs a val-rdy handshake to guarantee the timing correctness and data integrity. However, DRAM isn't even cleaver enough to hold massive amount of state of its own banks. In this way, the command sender needs to have some kinds of agreement with receiver, and that's what we called DDR spec (by JEDEC ofc).

## DDR commands timing

There are a lot of timing parameter tied with DDR issue system. They are designed to meet certain kinds of timing&power constraints. This section will explain following DDR timing parameters:

- tCK
- tRAS
- tCAS(tCL)
- tCWL
- tRCD
- tRP
- tCCD\_S && tCCD\_L
- tREFI
- tRFC
- tRPRE
- tWPRE
- tRRD\_S && tRRD\_L
- tWTR\_S && tWTR\_L
- tRTP
- tWR
- tFAW

There are even more parameters in spec, I just picked some of them that I care the most. 

The following will just be a re-interpretation of JEDEC spec. Spec didn't tell about what exactly are these timning parameters means(it do have waveform for each of them and a short description inside timing table).

---

***tCK*** is the period of clock signal. DDR memory does not have its own clock generator and it's relying on CPU's DDR interface to provide a reference clock. tCK can be something like 0.83 or 1.07 depends on DRAM frequency.

***tRAS*** stand for "Row Access Strobe". It represent the minimum amount of time between ACT and PRE. This parameter limits MC cannot issue an ACT and PRE back-to-back. It has to wait until the tRAS passed. The reason for such limitation will be explained when we talking about transistor level design.

***tCAS***(or tCL) stand for "Column Address Strobe". It measure the latency between the time when MC issue the RD and gets the first beats of data back. Note DRAM have a thing called "burst". This means data are sent in one chunk after one chunk, not all-at-once. ***tCAS*** only measure the latency between RD issued and first chunk of data arrived. It does not measure the whole RD delay.

***tCWL*** stand for "CAS Wrute Latency". From the name we can derive, it's the "***tCAS***" for WR. To be more clear, it define the latenct between issue out WR and the instance when DRAM start the write burst.

***tRCD*** stand for "RAS to CAS delay", it measure the time taken between ACT being issued and row ready for column command. It's easy to confuse with tRAS. The difference is, PRE is not column command, and it needs to wait until tRAS as satisfied, while RD/WR are column command, which only needs to wait until tRCD is satisfied. The reason for this will be covered when we talk about transistor level design.

***tRP*** stand for "Row Precharge". It means the time taken for single PRE command. Be aware the earlist timing to have precharge is tRAS after the last ACT. I will also cover the Precharge operation when we talked about transistor level design for Sense Amplifier.

***tCCD\_S && tCCD\_L*** stand for "Column to Column Delay(Short/Long)". This marks the minimum timing between issue two column command(RD/WR). In this case, MC cannot issue RD/WR command too fast, since that would cause problems in DRAM data integrity. The reason why we need Short/Long marks is the new technology introduced by DDR4 called bank groups. Bank group can be understand as an intermediate layer between channel and bank. Assume we have 32 banks per channel, to have 4 bank groups means we have 8 banks goes into one bank group. Bank groups share teh same address decoder, they also have their own local IO buses and SAs. Bank group are designed to fix the scalability issue of DRAM, as the storage density increase, the corresponding address decoder as well as bus wire also gets bigger. Designer divide whole structure into bank groups to keep boosting DRAM frequency.

It's faster for two RD to goes into different bank groups other than same one, because they do not have to share the same decoder and same local bus(still share the global bus since there's only one global bus, but it's okey). In this case, ***tCCD\_S*** is the minimum latency between two column command being issued when they target on different bank group, and ***tCCD\_L*** is the the minimum latency between two column command being issued when they target on same bank group.

***tREFI*** stand for "Refresh Interval". As the name reveal, it stand for how often a REFRESH command must be issued. As you probably already know, DRAM is neither self-amplified storage as SRAM/DFF nor permanent storage media like magnetic tape(or carving words on stones?). It needs to constantly read out what it got and re-amplify them. ***tREFI*** marks the period of doing such operation.

***tRFC*** stand for "ReFresh Cycle time". It stand for the time taken for DRAM to perform refresh. When DRAM performing refresh, no other DDR commands can be served and DRAM is basically passed away for ***tRFC*** amount of time.

***tRPRE*** stand for "Read PREamble time", which marks the pre-sampling delay from higher level. This is an internal timing parameter for interfacing which sit inside tCAS. The reason why we need to wait a while between data valid and sampling start is, DQ(data pin) are synchronized with DQS, but CK is the clock signal when we talked about DRAM operation like ACT/PRE/RD/WR. CK needs to travel a really long route from cpu to every DRAM chip, which can have serious clock skew problem. This means the CK we referred in sampling logic is not reliable for high-speed signal. In this case, DDR gives us another new clock signal called DQS. As the name suggested, it's the Sampling clock for DQ. DQS ***tRPRE*** is the time taken for DRAM to reset sampling logic and it's necessary for safe sampling to valid data.

***tWPRE*** stand for "Write PREamble time". It's basically same as tRPRE. The only place to notice is, DQ is a bidirectional signal wire, so for each column command, we need to go through the complete reset procedue of sampling. This means, both tRPRE and tWPRE is a part of tCAS.

There appearantly needs some CDC designs done to bridge two clock domain together. However, DRAM vendors are always slient on what exactly happening under the hood so we cannot know(We can make best guess tho). There are some research about DRAM reverse-engineering, but they mainly focused on subarray level design instead of interfacing. I'll talk about that research in this blog. And I really hope either vendor release more DRAM internal designs, or someone use SEM(scanning electron microscopy) to peel the DRAM and look it up.

***tRRD\_S && tRRD\_L*** stand for "Row to Row Delay(Short/Long)". It measure the minimal time between two success ACT being issued. ***tRRD\_S/L*** bound the frequency of issue ACT into different bank. Just like ***tCCD\_S/L*** differ the access into same/different bank group, ***tRRD\_S/L*** also differ the ACT goes into same/different bank group. The reason is also the same: different bank groups can have less confliction in parts use.


***tWTR\_S && tWTR\_L*** stand for "Write to Read delay(Long/Short)". It represent the minimum time delay for a RD after WR. For a RD after WR which falls into same bank group will be delayed for ***tWTR\_L***. If RD after WR falls into different bank group, they are going to be delayed for ***tWTR\_S***. The reason why we have this delay is, WR command actually write to local SA of target subarray, and it tooks a while to let the data re-amplify and store safely into 1t1c cell. This process is also called "Write Recovery". It means once CPU write something back, it also recharge the cell and protect it from wear-out.

***tRTP*** stand for "Read to Precharge delay". It represent the time delay from RD being issued and the point where PREC can be safely carried out. The reason is that, if we do not have this kinds of restriction, MC can issue precharge during the middle of RD. It's like you just enabled the wordline and precharge signal comes in and flush all you got in the cell. tRTP prevent this happen by delay next precharge into a time point when it can be safely carried out.

***tWR*** stand for "Write Recovery delay". It measure the delay from the end of write burst to the point where MC can safely precharge DRAM. This is a little bit different from ***tRTP***. It's because DRAM write operation including the time signal travel from DQ to local SA plus local SA amplify data and charge it back to cell. If we immediately precharge the SA after the last write, what might happen is precharge signal will arrive when last data is being written but not yet amplified back. This can cause data loss. ***tWR*** will hold the precharge after WR for a while to let charge completly recovered into cell storage.

***tFAW*** stand for "Four-Activate Window".  It's the time window which limits the number of activated bank in a channel. For example, if tFAW is 20 and at t=12 we already got 4 activated rows. If MC wants to activate another row within this channel at t=16, it have to wait until t >= 20 to issue the new activation. SPEC didn't tell why this exists, but people assume it's because we don't want to stress PDN too much.


## DRAM hierarchy
Conceptually, DRAM is a giant big matrix of 1t1c cell controlled by extremly long wordline and bitline. However, such design is not possible to manufactured within acceptable price. In this case, DRAM designer split huge amount of 1t1c cells into multiple layers. In traditioanl DDR4 memory, they are: Channel, Rank, Bank Group,  Bank, Subarray, Row, Column,

In other types of memory, there might be some difference compare to DDR4. For example HBM does not have rank, and LPDDR does not have bank group. This blog will focus on DDR4 so all below hierarchy are all in DDR4. I will talk about HBM more in next blog.

### Channel
Channel is the up-most hierarchy of DRAM. It usually takes at least 1 DIMM slot, and there's no restriction in issuing commands into two different channel. They are completly deparate hardware and do not share any global bus (if we ignore the internal DIMM bus inside CPU).

### Rank
Rank can be understood as a group of DRAM chip. DRAM chip is the black square you can found on DRAM pcb. You probably saw some DRAM parameter like ddr4 x16 3200. The x16 inside means each DRAM chip is able to provide 16bits at once. However, a single rank needs to provide 64bits output. In this case, we can calculate how many chips in one rank by using 64 / 16 = 4. Ranks are the driver for DQ pins, and there are at most one active rank at any time. CS# is the signal that MC used to select the target rank.

### Bank Group
Bank group is a new hierarhcy introduced by DDR4. It groups multiple banks together and they will share the same address decoder as well as same global data/control line. The reason is that DDR4 wants higher bandwidth compare with DDR3, but the frequency of bank is not really easy to increase (to be clear, it should be core frequency instead of bank frequency. But we haven't talked about DRAM core yet so we will use bank frequency here). Splitting banks into multiple bank groups can allow commands going to different bank group does not need to be constraints too much. For example, two column commands can pipeline the use of decode logics if we split into bank group. Without bank group, the second column command needs to wait for the first one finish and let it use the address decoder. Banks inside bankgroup do not operate in lock step. This means only one bank will be the driver of the bank group's output at anytime.

### Bank
Bank is the most important hierarchy in DRAM architecture. It consist of multiple small subarrays and sense-amplifier which is able to amplify and latch the result coming from those subarrys. Just like bank group, there can still be some parallism between bank and bank. For example, the banks in the same bank group can hold their own row buffer, but there can only be one bank be the driver for bankgroup's output.

### Subarray
Bank are made of subarray. Subarray is the actual place where you can see the matrix of 1t1c cell. Subarray usually have 8k width and 512/256 heights. Each subarray also comes with 8k sense-amplifier which is able to amplify and latch the charge in activaated row. This is what we call local row buffer. The column command over local row buffer is really fast, but if program missed this row buffer, subarray needs to precharge the current SA and activate the target row.


## Conceptual model for subarray

Subarray as the "core" of the DDR DRAM, which mean it is the place where data actually sitting in. As what we've covered previously, subarray basically is a matrix of 1t1c cells. Conceprually, when we want to access one cacheline of data from DRAM, a whole row from the target subarray will be activated, and DRAM select target data from the activated row. A row usually contain 8Kb data, but what CPU usually want for single access is just a cacheline of data(64bytes). 

Here is a conceptual figure of what is subarray:

[SUBARRAY PICTURE]

Once DRAM needs to access another row of data, it will first precharge currently activated row. During the precharge phase, precharge controller will electronically disconnect the currently activated bitcell with bitlines to retain data within capacitor, then it drive whole bitline into reference voltage by shorts the amplifier. After ***tRP*** amount of time, memory controller will issue an ACT command which will activat another row of bitcells by connecting a whole row of bitcells with bitlines, then charge will flows into local row buffer and being latched there.

Column select logic will control whether to connect the output of local rowbuffer up to global bitline(bank interface). Local row buffer is basically an array of Sense-Amplifier. Sense amplifier is able to amplify the voltage, but it also behave like an latch(tbc, it's actually a SR latch, but drived with a reference voltage). For now we just assume they are some special latch array which latch the output of activated row so they can be selected by column select logics.

Normally, one subarray can only have one activated row, and one bank can only have one activated subarray. Having multiple activated subarrys in one bank will result in charge sharing and undetermined behavior. 

One bank group can have multiple activated banks, but there's ***tFAW*** timing constraints to control the time window for 4 activated banks.

This subarray model is able to explain a lot of famous application of DRAM, for example, rowhammer[CITE] attack and computeDRAM[CITE]. If you just want to know how does DRAM works conceptually then here is the end.

## Break the conceptual model for subarray

Acutally, all things above are wrong...

The conceptual model can be used to explain most behavior of DRAM from the high level perspective. But once we need to customize subarray level DRAM design, there are a lot of place above doesn't really happen in real world.

### Incorrect place 0: Subarray is not the last level of DRAM hierarchy
It would be super neat if subarray is the last level. However, activation signal cannot travel all way down to 8k cells through wordline without lose it's signal integrity. Also, to have one wordline for every single row is not area efficient. In this case, DRAM vendor (afaik) further divided subarray into multiple MATS.

[PICTURE OF MATS IN SUBARRAY]

MATS can be imaged as a square of bitcells. Multiple mats stacked together to form a subarray. To further increase the storage capacity, vendor divided all wordlines into main wordlies and sub wordlines. Assume we have 512 rows, then we got (512/2 == 256) main wordlines and 2 sub-wordlines. Both main-wordlines and sub-wordlines are being feed into an AND gate per two mats. this AND gate can amplify the signal and drive the target rows when it's being selected by both main wordline and sub wordline.

[PICTURE OF MAIN/SUB-WORDLINES]

The implication behind this observation is, we cannot have fine-grain control of the row activation even if we hacked into subarray. For example, assume we only have 4 rows: 0, 1, 2, 3, and we have 4 wordlines: one for 0, 1, and one for 2, 3. Plus we also have 2 sub-wordline to select between main wordline. There is no way to activate row 0 and row 3 without activate row 2. Here is a picture to demonstrate this scenario:

[PICTURE OF ACT CONFLICTION]

A lot of DRAM design proposal assume fine-grain activation. Tbf they are all valid idea. The only problem is they also need to work on the special data placement inside DRAM to address this issue.

### Incorrect place 1: Subarray row buffer(Sense amplifier) is being shared by adjacent subarray

In previous description, each subarray has its own local row buffer. However, due to the needs of DRAM capacitor, having independent local row buffer for each subarray is not area effiicent. In this case, in open-bitline architecture(most wildly used DRAM architecture today), vendor choose to put half of the row buffer in one side of subarray and let adjacent subarray share it. The layout looks like this:

[PICTURE OF SA SHARING]

Another reason why split in this way is, sense amplifier needs to have a Vref to amplify the small pertubation. DRAM will use the idle(precharged) bitline from the adjacent subarray as the input of reference voltage. In this case, if one subarray is holding activated data, two adjacent subarray will lost half of its bandwidth. Here is an picture to illustrate this scenario:

[PICTURE OF ONE ACTIVATED SUBARRAY AND TWO IDLE NEIGHBOR]

This limination will constraints all the proposal mentioned about fine-grain subarray control. Same as Incorrect 0, they need to be clear on data placement.

### Incorrect place 2: GIO is smaller than what present in picture

GIO is the place where subarray's column selection logic output its result. It's being depicted as a bus to connect multiple subarray together, and sometime people think it's gonna be super cool to directly communicate through this bus. However, the bank interface is really small and due to the needs of storage capacity(Again???), this bus is really small. If we want to communicate within this narrow bus, each chunk of data needs to be sent out and latched at bank level amplifier. Then you can activate the target subarray's row and choose the correct place to write to. This procedure takes a long time and doesn't utilize the high bandwidth provided by subarray at all:

[PICTURE OF NARROW GIO]

If we really want in-bank communication, we need to add extra hardware to do this. LISA[CITE] is a good example, but it has more hidden constraints we'll cover later.

---
We can see, subarray level design should be carried out in cautions. We can have all crazy designs, but we need to be careful on these hidden constraints and clarify our assmption.

This is not even a full list of constraints. More constraints will be reveal in future chapters when we talked about transistor level design and reverse-engineering of today(2026)'s commercial DDR DRAM.


## Sense Amplifier
