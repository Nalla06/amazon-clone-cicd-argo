const fs = require('fs');
const path = require('path');

// The folder where your source files are located (e.g., 'src')
const directoryPath = path.join(__dirname, 'src'); // Change 'src' to your source folder if different

// Read the files in the directory
const files = fs.readdirSync(directoryPath);

// Loop through each file and process
files.forEach((file) => {
  const filePath = path.join(directoryPath, file);
  // Only process .jsx files
  if (fs.statSync(filePath).isFile() && filePath.endsWith('.jsx')) {
    let content = fs.readFileSync(filePath, 'utf8');

    // Replace invalid <a> tags with <button> tags
    content = content.replace(/<a href="">/g, '<button class="home-tile-details-buttons-play-a" onClick={handlePlay}>');
    content = content.replace(/<a href="#" role="button">/g, '<button class="home-tile-details-buttons-play-a" role="button">');
    
    // Additional adjustments for any other invalid <a> tags (if applicable)
    content = content.replace(/<a href=""/g, '<button class="home-tile-details-buttons-play-a" role="button">');
    
    // Write the modified content back to the file
    fs.writeFileSync(filePath, content, 'utf8');
  }
});

console.log("All files have been processed.");
