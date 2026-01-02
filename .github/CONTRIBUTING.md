# bigbio/relink: Contributing Guidelines

Hi there!
Many thanks for taking an interest in improving bigbio/relink.

We try to manage the required tasks for bigbio/relink using GitHub issues, you probably came to this page when creating one.
Please use the pre-filled template to save time.

However, don't be put off by this template - other more general issues and suggestions are welcome!
Contributions to the code are even more welcome ;)

## Contribution workflow

If you'd like to write some code for bigbio/relink, the standard workflow is as follows:

1. Check that there isn't already an issue about your idea in the [bigbio/relink issues](https://github.com/bigbio/relink/issues) to avoid duplicating work. If there isn't one already, please create one so that others know you're working on this
2. [Fork](https://help.github.com/en/github/getting-started-with-github/fork-a-repo) the [bigbio/relink repository](https://github.com/bigbio/relink) to your GitHub account
3. Make the necessary changes / additions within your forked repository following [Pipeline Conventions](https://nf-co.re/docs/contributing/guidelines/pipelines/overview)
4. Use `nf-core pipelines lint` to check that your code meets the nf-core guidelines
5. Ensure that any new features are covered with test coverage
6. Submit a Pull Request against the `dev` branch and wait for the code to be reviewed and merged

If you're not used to this workflow with git, you can start with some [docs from GitHub](https://help.github.com/en/github/collaborating-with-issues-and-pull-requests) or even their [determine-video](https://www.youtube.com/watch?v=w3jLJU7DT5E).

## Tests

You have the option to test your changes locally by running the pipeline. For receiving warnings about process selectors and other Nextflow config issues, you may want to run the pipeline with the debug profile. This will display warnings about unrecognized process selectors, which are typically hidden by default.

```bash
nextflow run . -profile debug,test,docker --outdir <OUTDIR>
```

## Getting help

For further information/help, please consult the [bigbio/relink documentation](https://github.com/bigbio/relink/blob/master/README.md) and don't hesitate to get in touch by opening an issue on our GitHub repository.

## Pipeline contribution conventions

To make the bigbio/relink code and processing logic more understandable for new contributors and to ensure quality, we semi-adhere to the following coding conventions:

1. Add trailing slash to all paths.
2. Use meaningful names for processes and variables.
3. Document your code.
4. Add comments to document code functionality.
5. Indent with spaces (4 spaces for Nextflow, 2 spaces for YAML).
6. Use lowercase for variable names.
7. Use uppercase for channel names.

