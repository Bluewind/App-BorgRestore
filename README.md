# NAME

App::BorgRestore - Restore paths from borg backups

# SYNOPSIS

    use App::BorgRestore;

# DESCRIPTION

App::BorgRestore is a restoration helper for borg.

It maintains a cache of borg backup contents (path and latest modification
time) and allows to quickly look up backups that contain a path. It further
supports restoring a path from an archive. The archive to be used can also be
automatically determined based on the age of the path.

The cache has to be updated regularly, ideally after creating or removing
backups.

**borg-restore.pl** is a wrapper around this class that allows for simple CLI
usage.

This package uses [Log::Any](https://metacpan.org/pod/Log::Any) for logging.

# LICENSE

Copyright (C) 2016-2017  Florian Pritz <bluewind@xinu.at>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see &lt;http://www.gnu.org/licenses/>.

See LICENSE for the full license text.

# AUTHOR

Florian Pritz <bluewind@xinu.at>
