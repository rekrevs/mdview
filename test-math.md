# Math Test Document

This document tests LaTeX math rendering in mdview.

## Inline Math

Einstein's famous equation: $E = mc^2$

The quadratic formula is $x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}$ and it's beautiful.

## Block Math

Here's the Gaussian integral:

$$\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}$$

And Euler's identity:

$$e^{i\pi} + 1 = 0$$

## Mixed Content

Regular markdown with **bold** and *italic* text works fine.

- List item 1
- List item 2 with math: $a^2 + b^2 = c^2$

> Blockquote test

### More Math

The sum of natural numbers:

$$\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}$$

Matrix example:

$$\begin{pmatrix} a & b \\ c & d \end{pmatrix}$$

## Code Block Test

```python
def quadratic(a, b, c):
    return (-b + (b**2 - 4*a*c)**0.5) / (2*a)
```

The end.
