# Learning Go

Code and examples from my journey to learn the Go language.

## The goal

I have wanted to experiment with developing in Go for a long time. 

Having worked (years ago) with C, C++, and Pascal variants, I expect that some of that experience (pointers and references, threading issues, general structure, "similar" syntax, C inheritance) will help.

**Why** 

I usually find that much of the actual backend code created in Node/Bun (what I have been using for the last few years) is easy to develop and start but ultimately very inefficient when running on *limited hardware*. 

By *limited hardware*, I mean a cheap VPS from a hosting provider that you can run for less than 10 USD/mo. Or releasing 100 autonomous web servers (each one serving ~10 concurrent users) on a single bare-metal server (Ryzen 7, 64 GB RAM, 1Gbit/s port) costing less than 70 USD/mo without bringing it to its knees.

But moving established and known code, practices, and running production software to a language I have no experience in at all always seemed like a VERY dangerous move. 

So, the move to Go had been postponed time and time again.

**Why now**

With the general availability of LLMs and coding agents, it now seems possible to migrate some of that code, or at least experiment with project ideas that have been floating around for some time. 

Ideas that may have immediate and practical results too: for example, the general architecture refactoring we made for the [ANALYTE's QUALIFY v6](https://github.com/analyte-com/qualify-web-project) could clearly benefit from these experiments:

- Easy deployment via a fully self-contained binary.
- Efficient serving of multiple users locally inside the client company network.
- Single light and fast multi-threaded workers in a single instance.
- Running a full LIMS in a dedicated server box located in the Lab itself (the Qbx project).

I have also been using OpenAI, Anthropic, and Open source models (Kimi, Qwen, and GLM) for continuous and real production work for the last 6 months. I have found Open source models (in particular GLM 4.0/5.1) to be quite capable in rigorous analysis of legacy codebases and generating good, solid and (highly important for me) readable and understandable code and documentation.

I have also made extensive use of Gemini (frequently) and ChatGPT (occasionally) to ask questions about Go, explore examples, and navigate friction points. I blatantly confess it encouraged me to start this journey. Ahhh, the relentless, exhausting stream of flattery and motivational fluff these chats keep pumping out!

So, I feel that it deserves a try to **use these tools** not just to generate productive code, but also **to serve as a learning companion**, easily creating examples, experimenting with architectural alternatives, and (very important for me) answering questions.

## How

I will create small examples of features I want to learn or experiment with inside this repo.

Each example will have its own folder with the code and a set of LLM-generated and updated files I regularly use in my work:

- **AGENTS.md**: General mandatory and IMPORTANT instructions for the assistant (like NEVER commit until requested, what to do when resuming a session, what to do on ending a session, etc.).
- **README.md**: Project overview, architecture, and code conventions.
- **MEMO.md**: The memento state of the last session, useful for keeping (some) context on resuming.
- **LEARNINGS.md**: Critical learnings we made in this session (like JS vs Go traps), to avoid repeating mistakes.
- **TODO.md**: List of pending issues.
- **PLAN.md**: Where the model can write the plan for a given request, and where I will comment and redirect in iterative passes until ready to go. 
- **DRAFT.md**: A "temp" board to write long comments and instructions while interacting with the coding assistant.

I will add to these files a special document:

- **QUESTIONS.md**: Where I will write my doubts and questions about topics related to the example or issues that may deserve further exploration. And, of course, it will contain the answers I found (or the ones the LLM can provide) for those questions.

I hope this document will be the logbook of that particular topic's learning, and that it may be of help to others.

## CONTRIBUTIONS

As this is a personal journey logbook, I do not yet have a clear picture now if it will be open to contributions. 

Suggestions, topics, better ways of doing things will always be welcomed, but **not sure I will have the time to review or include them**.

## DISCLAIMER

You will find here stupid and rather basic examples (and questions), and also some advanced explorations in no particular order. 

So **this is not a Go course**, but **rather a gathering of my own explorations learning Go**.



