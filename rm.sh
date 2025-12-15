#!/bin/bash
nix --extra-experimental-features "nix-command flakes" run . --impure