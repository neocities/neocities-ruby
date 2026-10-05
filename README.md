# The Neocities Gem

A CLI and library for using the Neocities API. Makes it easy to quickly upload, push, delete, and list your Neocities site.

## Installation

### Mac OSX

If you're using OSX (or already have ruby installed):

    gem install neocities

### Ubuntu/Debian

    sudo apt-get install ruby
    gem install neocities

### RHEL/AlmaLinux/RockyLinux
    sudo dnf install ruby
    gem install neocities

### Windows

Install ruby with [RubyInstaller](https://rubyinstaller.org/). Then you can install the gem with the above command.

### Running

After that, you are all set! Run `neocities` in a command line to see the options and get started.

### Authentication

The CLI uses an API key and never asks for your Neocities password. Create or copy a key from your site's [settings](https://neocities.org/settings), then paste it into the prompt the first time you run a command. The key is stored in your local Neocities config for later commands.

For CI or other automation, set `NEOCITIES_API_KEY` instead. Keys supplied through the environment are not saved locally.

Run `neocities logout -y` to remove a saved key from the computer. Regenerate the key in your site settings if you need to revoke it everywhere.

## Neocities::Client

This gem also ships with Neocities::Client, which you can use to write code that interfaces with the Neocities API.
