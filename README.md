# darktable_extra_scripts
Additional lua scripts for darktable that won't be included in the official repository or only tailored for my own personal needs

## Helicon Focus

This script adds a new panel to the lighttable that lets you export a couple of selected images and pass them to the (commercial) focus stacking application Helicon Focus.

The resulting image(s) are then imported into darktable again.

Optionally you can add new keywords to the imported image(s) and copy all keywords from the source images to the results.

## ExportToPublish

This script adds a storage destination for the export module that allows to copy the exported images into a specified destination directory, add some tags and optionally open the file manager to point to the folder (or image if a single image was exported).

It is inteded for exports that shall be published on some web service (online gallery, etc.) where I want to collect them in one folder and tag them with a special category to track which images are published on which services.

This storage will come with its own preset management since darktable currently does not allow scripts to participate in internal preset management.