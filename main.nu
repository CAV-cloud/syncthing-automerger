#!/usr/bin/env nu

def cleanup-stversions [] {
  let st_conflicts = (
      ^fd --hidden --type file sync-conflict $"($ROOT)/($STVERSIONS)"
      | lines
  )

# TODO Change message. Explain why these file should be deleted. Also say nothgin if none found
  print $"Found ($st_conflicts | length) conflict files."

  $st_conflicts
  | each {|f|
      print $"DELETE: ($f)"
      rm $f
  }

  print ""
}

def find-conflicts [] {
  print "Searching for Syncthing conflict files..."

  let conflicts = (
      ^fd  --hidden  --type file  sync-conflict  $ROOT  --exclude $STVERSIONS
      | lines
  )

  print $"Found ($conflicts | length) conflict files."

  $conflicts
  | each {|f|
      print $"  ($f)"
  }

  print ""
}

def merge-conflict [file: string] {

    print "----------------------------------------"
    print $"Conflict file: ($file)"

    let parsed = (
        $file
        | parse --regex '^(?<base>.*)\.sync-conflict-(?<date>\d{8})-(?<time>\d{6})-(?<id>[^.]+)\.(?<ext>.+)$'
    )

    if ($parsed | is-empty) {
        print "Regex did not match."
        return
    }

    let info = $parsed | first

    let original = $"($info.base).($info.ext)"

    print $"base     = ($info.base)"
    print $"date     = ($info.date)"
    print $"time     = ($info.time)"
    print $"id       = ($info.id)"
    print $"ext      = ($info.ext)"
    print $"original = ($original)"

    if not ($original | path exists) {
        print "Original doesn't exist."
        return
    }

    let st = ($ROOT | path join $STVERSIONS)

    print $"Looking for .stversions:"
    print $"  ($st)"

# TODO do not exist error:
    if ($st | path exists) {
      print ".stversions exists."
    }

    let relative = ($original | path relative-to $ROOT)
    print $"relative = ($relative)"


    let stem = ($relative | path parse | get stem)
    let ext = ($relative | path parse | get extension)

    print $"stem = ($stem)"
    print $"ext  = ($ext)"

    print "Contents:"


    let st_dir = ($st | path join ($original | path dirname | path relative-to $ROOT))
    print $"st_dir  = ($st_dir)"

    let latest_backup = (latest-backup $original)

    if ($latest_backup | is-empty) {
        print "No backup found."
        return
    }

    print ""
    print "================================="
    print "Merging"
    print $"Original : ($original)"
    print $"Base     : ($latest_backup)"
    print $"Conflict : ($file)"
    print ""

    # TODO do this more elegantly , remove the if statements? more concise
    let result = (
        do {
            ^git merge-file --union $original $latest_backup $file
        } | complete
    )

    if $result.exit_code != 0 {
        print "Merge failed!"
        print $result.stderr
    }
    if $result.exit_code == 0 {
      rm $file
      print "Merge succeeded."
    }
}



def latest-backup [original: string] {

    let relative = ($original | path relative-to $ROOT)
    let stem = ($relative | path parse | get stem)
    let ext = ($relative | path parse | get extension)

    let st_dir = (
        $ROOT
        | path join $STVERSIONS
        | path join ($original | path dirname | path relative-to $ROOT)
    )

    ^fd --hidden --type file . $st_dir
    | lines
    | where {|f|
        ($f | str contains $"($stem)~")
        and ($f | str ends-with $".($ext)")
    }
    | where {|f|
        (($f | path basename | split row "~") | length) == 2
    }
    | sort
    | last
}

def main [
    -d: string
] {
  print $"Running Syncthing automerger"

  # TODO error message if not existing:
  # eprintln!("Notes directory {} does not exist", notes_path);
  let ROOT = $d
  let STVERSIONS = ".stversions"

  print $"Watching directory: ($ROOT)"
  print ""

  cleanup-stversions

  (
  ^inotifywait
    --monitor
    --recursive
    # TODO All required events?
    -e create
    -e moved_to $ROOT
  | lines
  | each {|event|
      print $event

      find-conflicts
      | each {|file|
          merge-conflict $file
      }

      print "Automerging done!"
    }
  )
}
