import React from "react";
import ReactDOM from 'react-dom'
import HeaderComp from "./HeaderComp";
import BodyComp from "./BodyComp";
import FooterComp from "./FooterComp";

function App() {
  return (
    <body style={{ backgroundColor: "black" }}>
      <HeaderComp />
      <BodyComp />
      <FooterComp />
    </body>
  );
}

export default App;
