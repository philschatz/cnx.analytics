# Content Analytics

This package provides a service that runs javascript on content and metadata our repository,
collates the results, and presents them using programmable charts.

It's one of a series of related experiments of mine.

## Ideas

* If you save the server and client scripts you can have reports run periodically.
* The same UI could be used to make textbook tables far more interesting!
* Little reports on content like broken links, external links in a book, etc
* Include these charts on our website (ie Donate Page) and data is updated by `chron`

# Install

To install the dependencies run:

    npm install .

Next, verify things work by unzipping a complete ZIP and running a worker from the command line:

    cat worker/example-tag-frequency.js | time node worker/index.js -c ${PATH_TO_UNZIPPED_COLLECTIONS}

Now start the server up and point your browser to http://localhost:3000

    node --debug server/index.js --content-directory ${PATH_TO_UNZIPPED_COLLECTIONS}

## Debugging

You can debug the server by installing node-inspector and running:

    npm install -g node-inspector # installs node-inspector
    node-inspector &
    # Start up the commandline worker or the webserver
    # Point your browser to http://0.0.0.0:8080/debug?port=5858


## Documentation

Check out the [documentation](http://philschatz.github.com/cnx.analytics/docs/server.html)

Or, make it yourself by running:

    npm install --dev .
    ./node_modules/.bin/docco src/*.coffee

# Experiment Findings

This project was one of a series of experiments I did for http://cnx.org.
I've been using them to explore features, help define APIs, and provide some code to scavange.

My findings are organized below.

## Common Promise Structure

Having a common Promise JSON and URL structure makes writing monitoring code much easier.

I found I was using (and still am) the Copy/Paste antipattern to reuse both the
client and server logic to make an admin console. Things were _almost_ the same
but different enough that I still didn't monitoring/promises out.

Some properties (note: no id):

* status (WAITING, FAILED, FINISHED)
* created/modified
* progress.finished/warned/total since progress is optional and may not be known initially I made it a separate property
* history A list of strings (stdout from the task) for diagnosing

## Common Monitoring URL API

URL Suggestions to do monitoring:

* `/[noun]/[id]` where `[noun]` can be content (repo), tasks (analytics), pdfs, epubs, intermediates (transform services), or resources.
* `/[noun]` returns a JSON list of id's. Additional query parameters can filter that list (dates, completion, errors, etc)
* `/[noun]/[id].json` always returns the Promise so one can inspect the history of operations
* `/[noun]/[id]/kill` kills the task if it's running (and you have permission)

With that setup, you can take some monitoring Javascript code that makes a table
and just point it to `/noun` and all the stuff works.

### Kill Button

It ended up being very useful and not too difficult to implement.

By implementing it in conjunction with the admin console I realized the kill URL
should be relative to the task (`/task/[id]/kill` instead of `/kill/[id]`).


## Realtime Progress

I wanted to see progress while I waited for 10 minutes for a task to finish.

By seeing intermediate results I could:

* Tweak the chart code as I noticed things come in
* Notice patterns in clumps of content (few modules use a lot of emphasis tags in titles). This would not be apparent if I had just waited until the task completed


## Live Editing

Since running a task is a long process (30-60min) I tried to give the programmer
an idea of what their data will look like by providing some dummy content to work
with before submitting a Task.

I like how that turned out!

