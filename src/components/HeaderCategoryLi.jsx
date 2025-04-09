import React from "react";


function HeaderCategoryLi(props) {
  return (
    <li className="qwert-li">
      <a className="qwert-li-anchor" href="">
        {props.name}
      </a>
    </li>
  );
}

export default HeaderCategoryLi;
