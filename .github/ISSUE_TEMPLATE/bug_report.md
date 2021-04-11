name: 🐛 Bug Report
description: Submit a bug report to help us improve
body:
- type: checkboxes
  attributes:
    label: Prerequisites
    options:
    - label: I have written a descriptive issue title
      required: true
    - label: I have searched [open](https://github.com/SoftCreatR/imei/issues) and [closed](https://github.com/SoftCreatR/imei/issues?q=is%3Aissue+is%3Aclosed) issues to ensure it has not already been reported
      required: true
    - label: I have verified that I am using the latest version of IMEI
- type: input
  attributes:
    label: IMEI version
    placeholder: X.X-X
  validations:
    required: true
- type: dropdown
  attributes:
    label: Operating system
    options:
      - Linux
      - Windows
      - MacOS
      - Other (enter below)
  validations:
    required: true
- type: input
  attributes:
    label: Operating system, version and so on
  validations:
    required: true
- type: textarea
  attributes:
    label: Description
    description: A description of the bug
  validations:
    required: true
- type: textarea
  attributes:
    label: Steps to Reproduce
    description: List of steps, sample code, failing test or link to a project that reproduces the behavior. Make sure you place a stack trace inside a code (```) block to avoid linking unrelated issues.
  validations:
    required: true
- type: textarea
  attributes:
    label: Images
    description: Please upload images that can be used to reproduce issues in the area below. If the file type is not supported the file can be zipped and then uploaded instead.
