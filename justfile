set shell := ["bash", "-cu"]

default:
  @just --list

fmt:
  moon fmt

check:
  moon check

test:
  moon test

coverage:
  moon test --enable-coverage
