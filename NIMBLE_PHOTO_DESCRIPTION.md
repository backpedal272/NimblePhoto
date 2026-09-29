
NimblePhoto is a fast, keyboard-driven native MacOS desktop application for browsing and classifying large photo collections.
It is designed to handle 5,000–50,000 images efficiently.
The app never moves or deletes files.
It can read and process a variety of image formats, including JPG/JPEG, WEBP, PNG, HEIF/HEIC, TIFF, RAW (CR2, DNG, RAF) and reads EXIF information.
Thumbnails are saved in a Apple recommended folder (eg `~/Library/Caches/NimblePhoto/thumbnails`).
EXIF and other useful information is stored in an SQLite database in an Apple recommended location.
Classification uses NP macOS Finder tags, associated with a keystroke: 0-NP_Delete, 1-NP_Unclassified, 2-NP_Keep, 3-NP_Star, 4-NP_Select.
NP tags are read when accessing a folder, and updated immediately when user presses a keystroke or right-clicks on a file to pick a category. Any other tags are left untouched
A menu option allows to select the root folder of the pictures. It is remembered for the next session.

The app layout is traditional: folder tree on the left panel, thumbnails on the right, filtering bar at the top (categories), and status bar at the bottom.
The folder tree lists all folders below the selected root in a hierarchical tree view.
The filtering bar shows the categories with a counter for the selected folder. Clicking on a category filters the thumbnails accordingly.
The status bar shows information about the currently highlighted picture: name, dimension in pixels, date & time taken (EXIT DateTimeOriginal or file modification date), EXIF camera make and model.
The current folder and picture are highlighted.
Keyboard arrows allow navigation between thumbnails and folders. Tab switches between the folder tree and thumbnails.
Enter, space or click on a picture to show a full size image, scaled down to fit if needed.
When selecting a folder, the app loads its images into the thumbnail grid and checks thumbnails in the background for file addition, removal, or modification.
Selecting a folder loads its direct images into the thumbnail grid (not recursive).
Photos are sorted per ascending EXIF date taken, with filename as fallback for images without EXIF dates.
Thumbnails are scaled down in a square grid (300x300px) with laze rendering. A menu option allows to set the grid size. The file name and category is displayed below each thumbnail.
