#!/bin/bash

echo "Searching for Lambda functions..."
lambda_dirs=$(find ./lambda/ -name "main.go" -printf '%h\n' | sort -u)

lambda_count=$(echo "$lambda_dirs" | wc -l)
echo "Found $lambda_count Lambda function(s) to build"
echo ""

BUILD_DIR=$(realpath "$BUILD_DIR")
echo "Output directory: $BUILD_DIR"
mkdir -p "$BUILD_DIR"
echo ""

for dir in $lambda_dirs; do
  func_name=$(basename "$dir")

  echo "Building lambda function: $func_name"
  echo "  - Source: $dir"
  echo "  - Target: $BUILD_DIR/$func_name.zip"

  cd "$dir"

  output_binary="$BUILD_DIR/bootstrap"
  if GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -o "$output_binary" main.go; then
      binary_size=$(stat -c%s "$output_binary" | numfmt --to=iec-i --suffix=B)
      
      TZ=UTC touch -t 202001010000.00 "$output_binary"
      zip -X -j "$BUILD_DIR/$func_name.zip" "$output_binary"
      TZ=UTC touch -t 202001010000.00 "$BUILD_DIR/$func_name.zip"

      rm "$output_binary"
      echo "Build successful (size: $binary_size)"
  else
      echo "Error: Build failed"
      exit 1
  fi
  
  cd - > /dev/null
  echo ""
done

echo "All Lambda functions compiled successfully"
echo ""
